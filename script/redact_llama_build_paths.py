"""Remove the pinned llama.cpp XCFramework's CI checkout prefix before signing."""

from pathlib import Path
import os
import re
import stat
import struct
import sys
import tempfile


# Package.swift pins the upstream b12317 XCFramework. Only rewrite its known
# CI prefix on standalone source-file literals, not arbitrary absolute paths.
CI_PREFIX = b"/Users/" + b"runner/work/" + b"llama.cpp/llama.cpp/"
RELATIVE_PREFIX = b"llama.cpp/".ljust(len(CI_PREFIX), b"/")
SOURCE_FILE = re.compile(
    rb"(?:ggml|src|tools)/(?:[A-Za-z0-9_.+-]+/)*[A-Za-z0-9_.+-]+\.(?:c|cpp|h|m)"
)
MACH_O_64 = b"\xcf\xfa\xed\xfe"
FAT_MAGIC = b"\xca\xfe\xba\xbe"
SUPPORTED_CPUS = {0x01000007, 0x0100000C}  # x86_64 and arm64


def require(condition, problem):
    if not condition:
        raise ValueError(problem)


def macho_slices(data):
    if data.startswith(MACH_O_64):
        return [(0, len(data), None)]

    require(len(data) >= 8 and data.startswith(FAT_MAGIC), "unsupported Mach-O format")
    count = struct.unpack_from(">I", data, 4)[0]
    require(1 <= count <= len(SUPPORTED_CPUS), "unsupported Mach-O slice count")
    table_end = 8 + 20 * count
    require(table_end <= len(data), "truncated Mach-O slice table")
    slices = []
    seen_cpus = set()
    for entry in range(8, table_end, 20):
        cpu, _, start, length, _ = struct.unpack_from(">5I", data, entry)
        require(cpu in SUPPORTED_CPUS and cpu not in seen_cpus, "unexpected Mach-O CPU")
        require(
            table_end <= start <= start + length <= len(data),
            "Mach-O slice outside file",
        )
        seen_cpus.add(cpu)
        slices.append((start, length, cpu))
    slices.sort()
    require(
        all(a + size <= b for (a, size, _), (b, _, _) in zip(slices, slices[1:])),
        "overlapping Mach-O slices",
    )
    return slices


def cstring_section(data, start, length, fat_cpu):
    end = start + length
    require(length >= 32 and data[start:start + 4] == MACH_O_64, "invalid Mach-O slice")
    cpu, _, filetype, ncmds, sizeofcmds = struct.unpack_from("<5I", data, start + 4)
    require(cpu in SUPPORTED_CPUS and fat_cpu in (None, cpu), "Mach-O CPU mismatch")
    require(filetype == 6, "expected a Mach-O dynamic library")
    pos = start + 32
    commands_end = pos + sizeofcmds
    require(commands_end <= end and ncmds <= sizeofcmds // 8, "invalid load command table")
    section = None
    for _ in range(ncmds):
        require(pos + 8 <= commands_end, "truncated Mach-O load command")
        cmd, size = struct.unpack_from("<II", data, pos)
        cmd_end = pos + size
        require(size >= 8 and size % 8 == 0 and cmd_end <= commands_end, "invalid load command")
        if cmd == 0x19:  # LC_SEGMENT_64
            require(size >= 72, "truncated Mach-O segment")
            segment = data[pos + 8:pos + 24].rstrip(b"\0")
            nsects = struct.unpack_from("<I", data, pos + 64)[0]
            require(size == 72 + 80 * nsects, "invalid Mach-O section table")
            if segment == b"__TEXT":
                seg_off, seg_size = struct.unpack_from("<QQ", data, pos + 40)
                require(seg_off + seg_size <= length, "invalid Mach-O text segment")
                for sect in range(pos + 72, cmd_end, 80):
                    names = [x.rstrip(b"\0") for x in struct.unpack_from("<16s16s", data, sect)]
                    if names != [b"__cstring", b"__TEXT"]:
                        continue
                    _, sec_size, sec_off = struct.unpack_from("<QQI", data, sect + 32)
                    flags = struct.unpack_from("<I", data, sect + 64)[0]
                    require(section is None and flags & 0xff == 2, "invalid Mach-O cstring section")
                    require(
                        commands_end - start <= sec_off
                        and seg_off <= sec_off < sec_off + sec_size <= seg_off + seg_size,
                        "Mach-O cstring section outside text segment",
                    )
                    section = (start + sec_off, start + sec_off + sec_size)
        pos = cmd_end
    require(pos == commands_end and section is not None, "missing Mach-O cstring section")
    return section


def redact(data):
    positions = []
    for start, length, cpu in macho_slices(data):
        first, end = cstring_section(data, start, length, cpu)
        pos = first
        while (hit := data.find(CI_PREFIX, pos, end)) != -1:
            after_prefix = hit + len(CI_PREFIX)
            terminator = data.find(b"\0", after_prefix, end)
            require(
                (hit == first or data[hit - 1] == 0)
                and terminator != -1
                and SOURCE_FILE.fullmatch(data, after_prefix, terminator),
                "unexpected vendor source-path literal",
            )
            positions.append(hit)
            pos = terminator + 1
    require(data.count(CI_PREFIX) == len(positions), "vendor CI path outside expected literals")
    result = bytearray(data)
    for pos in positions:
        # Preserve offsets even for code holding pointers to suffixes.
        result[pos:pos + len(CI_PREFIX)] = RELATIVE_PREFIX
    return result, len(positions)


def redact_file(path):
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as source:
        meta = os.fstat(source.fileno())
        require(stat.S_ISREG(meta.st_mode), "expected a regular framework binary")
        result, count = redact(source.read())
    if count:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            replacement = Path(output.name)
            try:
                output.write(result)
                output.flush()
                os.fchmod(output.fileno(), stat.S_IMODE(meta.st_mode))
                os.replace(replacement, path)
            finally:
                replacement.unlink(missing_ok=True)
    return count


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: redact_llama_build_paths.py <staged framework binary>")
    try:
        count = redact_file(Path(sys.argv[1]))
    except ValueError as error:
        sys.exit(f"Could not redact llama.cpp build paths: {error}.")
    except OSError:
        sys.exit("Could not read or replace the staged llama.cpp framework binary.")
    print(f"Remapped {count} llama.cpp source-file paths.")
