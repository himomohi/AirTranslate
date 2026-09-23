#!/usr/bin/env bash
set -euo pipefail

INFO_PLIST="${1:?usage: write_info_plist.sh <Info.plist> <local|release>}"
PLIST_MODE="${2:?usage: write_info_plist.sh <Info.plist> <local|release>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=app_metadata.sh
source "$SCRIPT_DIR/app_metadata.sh"

if [[ "$PLIST_MODE" != "local" && "$PLIST_MODE" != "release" ]]; then
  echo "usage: write_info_plist.sh <Info.plist> <local|release>" >&2
  exit 2
fi

{
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
PLIST

  if [[ "$PLIST_MODE" == "release" ]]; then
    cat <<PLIST
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>LSApplicationCategoryType</key>
  <string>$CATEGORY</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>AirTranslate captures system audio only after you start capture so it can transcribe and translate what is playing on this Mac.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>AirTranslate can optionally capture microphone audio after you choose Microphone input and start capture.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>$COPYRIGHT_TEXT</string>
PLIST
  else
    cat <<PLIST
  <key>NSAppleEventsUsageDescription</key>
  <string>AirTranslate does not automate other apps.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>AirTranslate can optionally capture microphone audio after you choose Microphone input and start capture.</string>
  <key>NSSystemAudioCaptureUsageDescription</key>
  <string>AirTranslate captures Mac system audio so it can transcribe and translate what is playing.</string>
PLIST
  fi

  cat <<PLIST
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>AirTranslate uses speech recognition to convert captured Mac audio into live captions and translations.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
} >"$INFO_PLIST"
