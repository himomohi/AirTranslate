#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

OUTPUT_DIR="${1:?Pass the output directory for the static llama.xcframework.}"
if ! command -v cmake >/dev/null; then
  echo "CMake is required to build release artifacts." >&2
  exit 1
fi
REVISION=e0949d09b130707b3fa93d2cff616024231cf939
CACHE_DIR="$ROOT_DIR/.build/airtranslate-llama"
SOURCE_DIR="$CACHE_DIR/source-$REVISION"
CMAKE_DIR="$CACHE_DIR/native-$(uname -m)"
LIB_DIR="$CMAKE_DIR/lib"
HEADERS_DIR="$OUTPUT_DIR/headers"
mkdir -p "$CACHE_DIR" "$HEADERS_DIR"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone --quiet --depth 1 --branch b12317 \
    https://github.com/ggml-org/llama.cpp.git "$SOURCE_DIR"
fi
if [[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" != "$REVISION" \
      || -n "$(git -C "$SOURCE_DIR" status --porcelain)" ]]; then
  echo "The llama.cpp source must match the pinned, clean b12317 checkout." >&2
  exit 1
fi

# 컴파일러가 진단 메시지에 넣는 소스 경로도 상대 경로로 기록한다.
PREFIX_MAP="$(printf '%q' "-ffile-prefix-map=$SOURCE_DIR=llama.cpp")"
cmake -S "$SOURCE_DIR" -B "$CMAKE_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_SYSTEM_VERSION" \
  "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=$LIB_DIR" \
  "-DCMAKE_C_FLAGS=$PREFIX_MAP" \
  "-DCMAKE_CXX_FLAGS=$PREFIX_MAP" \
  "-DCMAKE_OBJC_FLAGS=$PREFIX_MAP" \
  -DBUILD_SHARED_LIBS=OFF -DGGML_BACKEND_DL=OFF -DGGML_NATIVE=OFF \
  -DGGML_BLAS=ON -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_OPENMP=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_COMMON=OFF -DLLAMA_OPENSSL=OFF
cmake --build "$CMAKE_DIR" --target llama --parallel "$(sysctl -n hw.logicalcpu)"

install -m 644 "$SOURCE_DIR/include/llama.h" "$HEADERS_DIR/"
install -m 644 "$SOURCE_DIR"/ggml/include/*.h "$HEADERS_DIR/"
cat > "$HEADERS_DIR/module.modulemap" <<'MODULEMAP'
module llama [system] {
    header "llama.h"
    export *
}
MODULEMAP

/usr/bin/libtool -static -o "$OUTPUT_DIR/libllama.a" \
  "$LIB_DIR/libllama.a" "$LIB_DIR/libggml.a" "$LIB_DIR/libggml-base.a" \
  "$LIB_DIR/libggml-cpu.a" "$LIB_DIR/libggml-blas.a" "$LIB_DIR/libggml-metal.a"
/usr/bin/xcodebuild -create-xcframework \
  -library "$OUTPUT_DIR/libllama.a" -headers "$HEADERS_DIR" \
  -output "$OUTPUT_DIR/llama.xcframework"
