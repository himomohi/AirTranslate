#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-zip}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/script"
# shellcheck source=app_metadata.sh
source "$SCRIPT_DIR/app_metadata.sh"
RELEASE_DIR="$ROOT_DIR/Release"
BUILD_DIR="$RELEASE_DIR/build"
PRODUCT_DIR="$RELEASE_DIR/product"
APP_BUNDLE="$PRODUCT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.entitlements"
ZIP_PATH="$PRODUCT_DIR/$APP_NAME-$VERSION-$BUILD_NUMBER.zip"
STABLE_ZIP_PATH="$PRODUCT_DIR/$APP_NAME-$VERSION.zip"
DMG_STAGING_DIR="$BUILD_DIR/dmg"
DMG_PATH="$PRODUCT_DIR/$APP_NAME.dmg"
DMG_SHA256_PATH="$PRODUCT_DIR/$APP_NAME.dmg.sha256"
VERSIONED_DMG_PATH="$PRODUCT_DIR/$APP_NAME-$VERSION.dmg"
VERSIONED_DMG_SHA256_PATH="$PRODUCT_DIR/$APP_NAME-$VERSION.dmg.sha256"

usage() {
  cat <<EOF
usage: $0 [zip|dmg|all]

zip  Build an Apache 2.0 open-source release app bundle and ZIP.
dmg  Build an Apache 2.0 open-source release app bundle and DMG.
all  Build both ZIP and DMG release artifacts.

Optional:
  BUNDLE_ID, VERSION, BUILD_NUMBER, MIN_SYSTEM_VERSION
EOF
}

case "$MODE" in
  zip|dmg|all)
    ;;
  --help|-h|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

cd "$ROOT_DIR"

rm -rf "$BUILD_DIR" "$APP_BUNDLE"
mkdir -p "$BUILD_DIR" "$PRODUCT_DIR" "$APP_MACOS" "$APP_RESOURCES"
rm -f \
  "$ZIP_PATH" \
  "$STABLE_ZIP_PATH" \
  "$DMG_PATH" \
  "$DMG_SHA256_PATH" \
  "$VERSIONED_DMG_PATH" \
  "$VERSIONED_DMG_SHA256_PATH"

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

install -m 755 "$BUILD_BINARY" "$APP_BINARY"
install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
install -m 644 "$ROOT_DIR/LICENSE" "$APP_RESOURCES/LICENSE"
install -m 644 "$ROOT_DIR/NOTICE" "$APP_RESOURCES/NOTICE"

"$SCRIPT_DIR/write_info_plist.sh" "$INFO_PLIST" release

/usr/bin/plutil -lint "$INFO_PLIST"

CODESIGN_ARGS=(
  --force
  --deep
  --strict
  --options runtime
  --entitlements "$ENTITLEMENTS_PATH"
  --sign "$SIGNING_IDENTITY"
)

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  CODESIGN_ARGS+=(--timestamp=none)
fi

/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$MODE" == "zip" || "$MODE" == "all" ]]; then
  /usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  /usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$STABLE_ZIP_PATH"
fi

if [[ "$MODE" == "dmg" || "$MODE" == "all" ]]; then
  rm -rf "$DMG_STAGING_DIR"
  mkdir -p "$DMG_STAGING_DIR"
  /usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
  /usr/bin/hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  /bin/cp -p "$DMG_PATH" "$VERSIONED_DMG_PATH"
  (cd "$PRODUCT_DIR" && /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_SHA256_PATH")")
  (cd "$PRODUCT_DIR" && /usr/bin/shasum -a 256 "$(basename "$VERSIONED_DMG_PATH")" > "$(basename "$VERSIONED_DMG_SHA256_PATH")")
fi

echo "Built open-source release app: $APP_BUNDLE"
if [[ "$MODE" == "zip" || "$MODE" == "all" ]]; then
  echo "Built open-source release zip: $ZIP_PATH"
  echo "Built stable release zip: $STABLE_ZIP_PATH"
fi
if [[ "$MODE" == "dmg" || "$MODE" == "all" ]]; then
  echo "Built open-source release dmg: $DMG_PATH"
  echo "Built open-source release dmg checksum: $DMG_SHA256_PATH"
  echo "Built versioned release dmg: $VERSIONED_DMG_PATH"
  echo "Built versioned release dmg checksum: $VERSIONED_DMG_SHA256_PATH"
fi
