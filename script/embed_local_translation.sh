#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="$1"
BUILD_BINARY="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_SOURCE="$(dirname "$BUILD_BINARY")/llama.framework"
FRAMEWORKS="$APP_BUNDLE/Contents/Frameworks"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$(basename "$BUILD_BINARY")"
[[ -d "$FRAMEWORK_SOURCE" ]] || { echo "Missing SwiftPM llama.framework" >&2; exit 1; }
mkdir -p "$FRAMEWORKS" "$APP_BUNDLE/Contents/Resources/ThirdParty"
/usr/bin/ditto "$FRAMEWORK_SOURCE" "$FRAMEWORKS/llama.framework"
/usr/bin/strip -S "$FRAMEWORKS/llama.framework/Versions/A/llama"
# SwiftPM의 개발 머신 경로 대신 번들 내부 Frameworks만 사용한다.
while IFS= read -r rpath; do
  if [[ "$rpath" == /* ]]; then
    /usr/bin/install_name_tool -delete_rpath "$rpath" "$APP_BINARY"
  fi
done < <(/usr/bin/otool -l "$APP_BINARY" | /usr/bin/awk '/cmd LC_RPATH/{found=1; next} found && $1=="path"{sub(/^[[:space:]]*path /, ""); sub(/ \(offset.*$/, ""); print; found=0}')
/usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
/bin/cp "$ROOT_DIR/Resources/ThirdParty/llama.cpp-LICENSE.txt" "$ROOT_DIR/Resources/ThirdParty/Hy-MT2-LICENSE.txt" \
  "$APP_BUNDLE/Contents/Resources/ThirdParty/"
