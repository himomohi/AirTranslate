import importlib.util
import os
from pathlib import Path
import struct
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "redact_llama_build_paths.py"
SPEC = importlib.util.spec_from_file_location("redact_llama_build_paths", MODULE_PATH)
REDACTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REDACTOR)
ARM64 = 0x0100000C
X86_64 = 0x01000007


def thin(cpu, strings, tail=b"", section_flags=2):
    header_size = 32
    command_size = 72 + 80
    offset = header_size + command_size
    header = struct.pack(
        "<8I", 0xFEEDFACF, cpu, 0, 6, 1, command_size, 0, 0
    )
    segment = struct.pack(
        "<II16sQQQQIIII",
        0x19, command_size, b"__TEXT", 0, offset + len(strings),
        0, offset + len(strings), 5, 5, 1, 0,
    )
    section = struct.pack(
        "<16s16sQQIIIIIIII",
        b"__cstring", b"__TEXT", offset, len(strings), offset,
        0, 0, 0, section_flags, 0, 0, 0,
    )
    return header + segment + section + strings + tail


def universal(*slices):
    start = 8 + 20 * len(slices)
    fat = struct.pack(">II", 0xCAFEBABE, len(slices))
    for cpu, data in slices:
        fat += struct.pack(">5I", cpu, 0, start, len(data), 0)
        start += len(data)
    return fat + b"".join(data for _, data in slices)


class RedactLlamaBuildPathsTests(unittest.TestCase):
    def test_both_slices_match_without_changing_other_bytes(self):
        prefix = REDACTOR.CI_PREFIX
        source = b"src/tree/model.cpp\0"
        other = b"/Users/someone/local/file.cpp\0/tmp/XXXXXX\0"
        arm = thin(ARM64, prefix + source + other, b"arm64 tail")
        intel = thin(X86_64, b"before\0" + prefix + source, b"x86_64 tail")
        raw = universal((X86_64, intel), (ARM64, arm))
        result, count = REDACTOR.redact(raw)
        self.assertEqual(count, 2)
        self.assertEqual(len(result), len(raw))
        self.assertEqual(result, raw.replace(prefix, REDACTOR.RELATIVE_PREFIX))
        self.assertEqual(REDACTOR.redact(result), (result, 0))

    def test_known_prefix_outside_cstring_fails_closed(self):
        strings = b"other string\0"
        binary = thin(ARM64, strings, REDACTOR.CI_PREFIX + b"src/file.cpp\0")
        with self.assertRaisesRegex(ValueError, "outside expected literals"):
            REDACTOR.redact(binary)

    def test_known_prefix_inside_a_larger_string_fails_closed(self):
        binary = thin(ARM64, b"diagnostic " + REDACTOR.CI_PREFIX + b"src/file.cpp\0")
        with self.assertRaisesRegex(ValueError, "unexpected vendor source-path"):
            REDACTOR.redact(binary)

    def test_unexpected_or_unterminated_source_literal_fails_closed(self):
        for tail in (b"src/file.cpp %s\0", b"src/file.cpp", b"test/file.cpp\0"):
            with self.subTest(tail=tail):
                with self.assertRaisesRegex(ValueError, "unexpected vendor source-path"):
                    REDACTOR.redact(thin(ARM64, REDACTOR.CI_PREFIX + tail))

    def test_malformed_macho_fails_closed(self):
        for image in (
            b"bad",
            thin(ARM64, b"t\0", section_flags=1),
            thin(ARM64, b"t\0")[:-1],
            universal((X86_64, thin(ARM64, b"t\0"))),
        ):
            with self.subTest(size=len(image)):
                with self.assertRaises(ValueError):
                    REDACTOR.redact(image)

    def test_file_replace_preserves_mode_and_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as root:
            binary = Path(root) / "llama"
            binary.write_bytes(thin(ARM64, REDACTOR.CI_PREFIX + b"ggml/src/ops.c\0"))
            binary.chmod(0o755)
            link = binary.with_name("link")
            link.symlink_to(binary)
            with self.assertRaises(OSError):
                REDACTOR.redact_file(link)
            self.assertIn(REDACTOR.CI_PREFIX, binary.read_bytes())
            self.assertEqual(REDACTOR.redact_file(binary), 1)
            self.assertEqual(os.stat(binary).st_mode & 0o777, 0o755)
            self.assertNotIn(REDACTOR.CI_PREFIX, binary.read_bytes())


if __name__ == "__main__":
    unittest.main()
