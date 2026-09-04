#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/script"
# shellcheck source=app_metadata.sh
source "$SCRIPT_DIR/app_metadata.sh"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.entitlements"
DEBUG_ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.debug.entitlements"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
BUILD_CONFIGURATION="debug"

case "$MODE" in
  --debug|debug)
    ENTITLEMENTS_PATH="$DEBUG_ENTITLEMENTS_PATH"
    ;;
  --build-only|build-only)
    BUILD_CONFIGURATION="release"
    ;;
esac

cd "$ROOT_DIR"

case "$MODE" in
  --build-only|build-only)
    ;;
  *)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    ;;
esac

swift build --configuration "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build --configuration "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"

"$SCRIPT_DIR/write_info_plist.sh" "$INFO_PLIST" local

select_code_sign_identity() {
  if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi

  /usr/bin/security find-identity -v -p codesigning 2>/dev/null |
    /usr/bin/awk -F'"' '/"Apple Development:|Developer ID Application:|Mac Developer:/{ print $2; exit }'
}

SIGN_IDENTITY="$(select_code_sign_identity)"
if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PATH" --timestamp=none --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  /usr/bin/codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PATH" --sign - "$APP_BUNDLE"
  echo "warning: no persistent code signing identity found; macOS privacy grants may reset after rebuilds" >&2
fi

open_app() {
  /usr/bin/nohup "$APP_BINARY" >"$DIST_DIR/$APP_NAME.log" 2>&1 &
}

verify_running_app() {
  local pid
  local command
  pid="$(/usr/bin/pgrep -n -x "$APP_NAME" || true)"
  [[ -n "$pid" ]] || {
    echo "$APP_NAME did not start" >&2
    return 1
  }
  command="$(/bin/ps -p "$pid" -o command=)"
  [[ "$command" == "$APP_BINARY" ]] || {
    echo "Expected $APP_BINARY, but PID $pid is running $command" >&2
    return 1
  }
}

case "$MODE" in
  --build-only|build-only)
    echo "Built $APP_BUNDLE"
    ;;
  --reset-permissions|reset-permissions)
    /usr/bin/defaults delete "$BUNDLE_ID" "AirTranslate.screenRecordingAccessRequestAttempted" >/dev/null 2>&1 || true
    /usr/bin/tccutil reset ScreenCapture "$BUNDLE_ID" || true
    /usr/bin/tccutil reset AudioCapture "$BUNDLE_ID" || true
    /usr/bin/tccutil reset Microphone "$BUNDLE_ID" || true
    /usr/bin/tccutil reset SpeechRecognition "$BUNDLE_ID" || true
    echo "Reset AirTranslate privacy grants. Relaunch and approve Screen Recording, System Audio Recording, Microphone (when selected), and Speech Recognition once."
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    verify_running_app
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify|--reset-permissions]" >&2
    exit 2
    ;;
esac
