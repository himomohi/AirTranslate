#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=app_metadata.sh
source "$ROOT_DIR/script/app_metadata.sh"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.entitlements"
DEBUG_ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.debug.entitlements"
LOCAL_BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"
RELEASE_BUILD_SCRIPT="$ROOT_DIR/Release/build_open_source_release.sh"
PLIST_WRITER="$ROOT_DIR/script/write_info_plist.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airtranslate-packaging-permissions.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

require_pattern() {
  local pattern="$1"
  local path="$2"
  if ! /usr/bin/grep -Fq -- "$pattern" "$path"; then
    echo "missing required packaging permission configuration in $path: $pattern" >&2
    exit 1
  fi
}

entitlement_is_true() {
  local plist_path="$1"
  local entitlement_key="$2"
  local value
  value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement_key" "$plist_path" 2>/dev/null || true)"
  [[ "$value" == "true" ]]
}

assert_entitlement_is_true() {
  local plist_path="$1"
  local entitlement_key="$2"
  local label="$3"
  if ! entitlement_is_true "$plist_path" "$entitlement_key"; then
    echo "$label must set $entitlement_key to the Boolean true" >&2
    exit 1
  fi
}

assert_entitlement_is_absent() {
  local plist_path="$1"
  local entitlement_key="$2"
  local label="$3"
  if /usr/libexec/PlistBuddy -c "Print :$entitlement_key" "$plist_path" >/dev/null 2>&1; then
    echo "$label must not contain $entitlement_key" >&2
    exit 1
  fi
}

write_embedded_entitlements() {
  local app_bundle="$1"
  local destination="$2"
  /usr/bin/codesign -d --entitlements :- "$app_bundle" >"$destination" 2>/dev/null
  /usr/bin/plutil -lint "$destination" >/dev/null
}

assert_hardened_runtime() {
  local app_bundle="$1"
  local details_path="$TEMP_DIR/codesign-details.txt"
  /usr/bin/codesign -dvv "$app_bundle" >"$details_path" 2>&1
  if ! /usr/bin/grep -Eq 'flags=.*runtime' "$details_path"; then
    echo "Hardened Runtime flag is missing from $app_bundle" >&2
    exit 1
  fi
}

assert_entitlement_is_true "$ENTITLEMENTS_PATH" 'com.apple.security.device.audio-input' 'release entitlement source'
assert_entitlement_is_absent "$ENTITLEMENTS_PATH" 'com.apple.security.get-task-allow' 'release entitlement source'
assert_entitlement_is_true "$DEBUG_ENTITLEMENTS_PATH" 'com.apple.security.device.audio-input' 'debug entitlement source'
assert_entitlement_is_true "$DEBUG_ENTITLEMENTS_PATH" 'com.apple.security.get-task-allow' 'debug entitlement source'

FALSE_ENTITLEMENTS="$TEMP_DIR/false-audio-input-with-unrelated-true.entitlements"
/bin/cp "$ENTITLEMENTS_PATH" "$FALSE_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Set :com.apple.security.device.audio-input false' "$FALSE_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Add :com.example.unrelated bool true' "$FALSE_ENTITLEMENTS"
if entitlement_is_true "$FALSE_ENTITLEMENTS" 'com.apple.security.device.audio-input'; then
  echo "audio-input=false must fail even when an unrelated entitlement is true" >&2
  exit 1
fi

for signing_script in "$LOCAL_BUILD_SCRIPT" "$RELEASE_BUILD_SCRIPT"; do
  require_pattern '--options runtime' "$signing_script"
  require_pattern '--entitlements "$ENTITLEMENTS_PATH"' "$signing_script"
done

require_pattern 'rm -rf "$BUILD_DIR" "$APP_BUNDLE"' "$RELEASE_BUILD_SCRIPT"
require_pattern 'mkdir -p "$BUILD_DIR" "$PRODUCT_DIR"' "$RELEASE_BUILD_SCRIPT"
if /usr/bin/grep -Fq 'rm -rf "$BUILD_DIR" "$PRODUCT_DIR"' "$RELEASE_BUILD_SCRIPT"; then
  echo "release builds must preserve older files in Release/product" >&2
  exit 1
fi

require_pattern 'DEBUG_ENTITLEMENTS_PATH=' "$LOCAL_BUILD_SCRIPT"
require_pattern '--debug|debug)' "$LOCAL_BUILD_SCRIPT"
require_pattern 'ENTITLEMENTS_PATH="$DEBUG_ENTITLEMENTS_PATH"' "$LOCAL_BUILD_SCRIPT"
if /usr/bin/grep -Fq 'AirTranslate.debug.entitlements' "$RELEASE_BUILD_SCRIPT"; then
  echo "release signing must not use the debug entitlement file" >&2
  exit 1
fi

require_pattern 'tccutil reset Microphone "$BUNDLE_ID"' "$LOCAL_BUILD_SCRIPT"
require_pattern 'defaults delete "$BUNDLE_ID" "AirTranslate.screenRecordingAccessRequestAttempted"' "$LOCAL_BUILD_SCRIPT"
require_pattern 'Microphone (when selected)' "$LOCAL_BUILD_SCRIPT"
require_pattern 'pgrep -x "$APP_NAME"' "$LOCAL_BUILD_SCRIPT"
require_pattern '/usr/bin/open --stdout' "$LOCAL_BUILD_SCRIPT"
if /usr/bin/grep -Fq 'pkill -x "$APP_NAME"' "$LOCAL_BUILD_SCRIPT"; then
  echo "the local launcher must not terminate an existing AirTranslate instance" >&2
  exit 1
fi
require_pattern '"$APP_BUNDLE"' "$LOCAL_BUILD_SCRIPT"
require_pattern 'verify_running_app' "$LOCAL_BUILD_SCRIPT"
require_pattern 'Expected $APP_BINARY' "$LOCAL_BUILD_SCRIPT"

SETTINGS_VIEW="$ROOT_DIR/Sources/AirTranslate/Views/SettingsView.swift"
LIVE_OUTPUT_PICKER="$ROOT_DIR/Sources/AirTranslate/Views/LiveOutputModePicker.swift"
RELEASE_VERIFY_WORKFLOW="$ROOT_DIR/.github/workflows/release-verify.yml"
require_pattern '.accessibilityRespondsToUserInteraction(!isDisabled)' "$LIVE_OUTPUT_PICKER"
settings_accessibility_barrier_count="$(
  /usr/bin/grep -Fc '.accessibilityRespondsToUserInteraction' "$SETTINGS_VIEW"
)"
if [[ "$settings_accessibility_barrier_count" -lt 5 ]]; then
  echo "locked Settings segmented controls must block accessibility user interaction" >&2
  exit 1
fi
require_pattern 'isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation' "$SETTINGS_VIEW"
require_pattern '/usr/bin/grep -aERq' "$RELEASE_VERIFY_WORKFLOW"
if /usr/bin/grep -Fq '/usr/bin/grep -aERn' "$RELEASE_VERIFY_WORKFLOW"; then
  echo "release secret scanning must not print matching credential lines" >&2
  exit 1
fi

assert_no_dynamic_disabled_after_segmented_picker() {
  local violations
  if ! violations="$(
    /usr/bin/find "$ROOT_DIR/Sources" -name '*.swift' -type f -print0 |
      /usr/bin/xargs -0 /usr/bin/awk '
        /\.pickerStyle\(\.segmented\)/ {
          remaining = 12
          picker_line = FNR
          next
        }
        remaining > 0 {
          if ($0 ~ /\.disabled\(/) {
            print FILENAME ":" FNR ": dynamic .disabled(...) near segmented Picker at line " picker_line
            found = 1
          }
          remaining--
        }
        END { exit found ? 1 : 0 }
      '
  )"; then
    echo "segmented Pickers must keep their AppKit enabled state stable:" >&2
    echo "$violations" >&2
    exit 1
  fi
}

assert_no_dynamic_disabled_after_segmented_picker

for mode in local release; do
  plist_path="$TEMP_DIR/$mode-Info.plist"
  "$PLIST_WRITER" "$plist_path" "$mode"
  /usr/bin/plutil -lint "$plist_path" >/dev/null
  if ! /usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$plist_path" >/dev/null; then
    echo "NSMicrophoneUsageDescription is missing from the $mode Info.plist" >&2
    exit 1
  fi
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMultipleInstancesProhibited' "$plist_path")" != "true" ]]; then
    echo "LSMultipleInstancesProhibited must be true in the $mode Info.plist" >&2
    exit 1
  fi
done

TEST_APP="$TEMP_DIR/$APP_NAME.app"
mkdir -p "$TEST_APP/Contents/MacOS"
/bin/cp "$TEMP_DIR/local-Info.plist" "$TEST_APP/Contents/Info.plist"
/bin/cp /usr/bin/true "$TEST_APP/Contents/MacOS/AirTranslate"
/usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS_PATH" --sign - "$TEST_APP"
EMBEDDED_RELEASE_ENTITLEMENTS="$TEMP_DIR/embedded-release.entitlements"
write_embedded_entitlements "$TEST_APP" "$EMBEDDED_RELEASE_ENTITLEMENTS"
assert_entitlement_is_true "$EMBEDDED_RELEASE_ENTITLEMENTS" 'com.apple.security.device.audio-input' 'embedded release entitlement'
assert_entitlement_is_absent "$EMBEDDED_RELEASE_ENTITLEMENTS" 'com.apple.security.get-task-allow' 'embedded release entitlement'
assert_hardened_runtime "$TEST_APP"

/usr/bin/codesign --force --options runtime --entitlements "$DEBUG_ENTITLEMENTS_PATH" --sign - "$TEST_APP"
EMBEDDED_DEBUG_ENTITLEMENTS="$TEMP_DIR/embedded-debug.entitlements"
write_embedded_entitlements "$TEST_APP" "$EMBEDDED_DEBUG_ENTITLEMENTS"
assert_entitlement_is_true "$EMBEDDED_DEBUG_ENTITLEMENTS" 'com.apple.security.device.audio-input' 'embedded debug entitlement'
assert_entitlement_is_true "$EMBEDDED_DEBUG_ENTITLEMENTS" 'com.apple.security.get-task-allow' 'embedded debug entitlement'
assert_hardened_runtime "$TEST_APP"

echo "Packaging permission checks passed."
