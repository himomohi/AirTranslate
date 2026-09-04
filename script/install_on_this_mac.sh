#!/usr/bin/env bash
set -euo pipefail

# Build the privacy-fixed AirTranslate branch locally and install it for the
# current macOS user. No API keys or saved application data are copied.

REPOSITORY_URL="${AIRTRANSLATE_REPOSITORY_URL:-https://github.com/gary8020/AirTranslate.git}"
SOURCE_REVISION="${AIRTRANSLATE_SOURCE_REVISION:-${AIRTRANSLATE_SOURCE_BRANCH:-distribution/cross-mac-installer}}"
SOURCE_DIR="${AIRTRANSLATE_SOURCE_DIR:-${HOME}/Library/Application Support/AirTranslate Custom Build/source}"
INSTALL_DIR="${AIRTRANSLATE_INSTALL_DIR:-${HOME}/Applications}"
BACKUP_DIR="${AIRTRANSLATE_BACKUP_DIR:-$(dirname "$SOURCE_DIR")/backups}"
APP_NAME="AirTranslate"
APP_SOURCE="$SOURCE_DIR/dist/$APP_NAME.app"
APP_TARGET="$INSTALL_DIR/$APP_NAME.app"
APP_BINARY="$APP_TARGET/Contents/MacOS/$APP_NAME"
BACKUP_PATH="$BACKUP_DIR/$APP_NAME-previous.app"
LOCK_DIR="$(dirname "$SOURCE_DIR")/.installer.lock"
MODE="${1:-install}"
STAGING_DIR=""
LOCK_HELD="false"
SWAP_COMPLETE="false"
INSTALL_COMPLETE="false"
BACKUP_CREATED_THIS_RUN="false"

fail() {
  echo "AirTranslate installer: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

cleanup() {
  if [[ "$INSTALL_COMPLETE" != "true" ]]; then
    if [[ "$SWAP_COMPLETE" == "true" && -e "$APP_TARGET" ]]; then
      rm -rf -- "$APP_TARGET"
    fi
    if [[ "$BACKUP_CREATED_THIS_RUN" == "true" && -e "$BACKUP_PATH" ]]; then
      if [[ -e "$APP_TARGET" ]]; then
        rm -rf -- "$APP_TARGET"
      fi
      mv "$BACKUP_PATH" "$APP_TARGET" || true
    fi
  fi
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf -- "$STAGING_DIR"
  fi
  if [[ "$LOCK_HELD" == "true" ]]; then
    rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

check_mac() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "this installer runs only on macOS"
  [[ "$(uname -m)" == "arm64" ]] || fail "this build currently supports Apple Silicon Macs only"

  local major_version
  major_version="$(sw_vers -productVersion | cut -d. -f1)"
  [[ "$major_version" =~ ^[0-9]+$ ]] || fail "could not determine the macOS version"
  (( major_version >= 26 )) || fail "macOS 26 or later is required"

  require_command git
  require_command swift
  require_command xcode-select
  require_command codesign
  require_command ditto
  xcode-select -p >/dev/null 2>&1 || fail "install Xcode Command Line Tools first: xcode-select --install"
}

prepare_source() {
  if [[ -e "$SOURCE_DIR" && ! -d "$SOURCE_DIR/.git" ]]; then
    fail "$SOURCE_DIR exists but is not an AirTranslate Git checkout"
  fi

  if [[ -d "$SOURCE_DIR/.git" ]]; then
    local current_repository_url
    current_repository_url="$(git -C "$SOURCE_DIR" remote get-url origin)"
    [[ "$current_repository_url" == "$REPOSITORY_URL" ]] ||
      fail "$SOURCE_DIR points to $current_repository_url instead of $REPOSITORY_URL"
    [[ -z "$(git -C "$SOURCE_DIR" status --short)" ]] ||
      fail "$SOURCE_DIR has local changes; move or commit them before updating"
    git -C "$SOURCE_DIR" fetch --prune origin "$SOURCE_REVISION"
  else
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone --no-checkout "$REPOSITORY_URL" "$SOURCE_DIR"
    git -C "$SOURCE_DIR" fetch origin "$SOURCE_REVISION"
  fi

  git -C "$SOURCE_DIR" switch --detach FETCH_HEAD

  if [[ "$SOURCE_REVISION" =~ ^[0-9a-fA-F]{40}$ ]]; then
    local expected_revision
    local actual_revision
    expected_revision="$(printf '%s' "$SOURCE_REVISION" | tr '[:upper:]' '[:lower:]')"
    actual_revision="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
    [[ "$actual_revision" == "$expected_revision" ]] ||
      fail "fetched $actual_revision instead of requested commit $expected_revision"
  fi
}

acquire_lock() {
  mkdir -p "$(dirname "$SOURCE_DIR")"
  mkdir "$LOCK_DIR" 2>/dev/null || fail "another AirTranslate install is already running"
  LOCK_HELD="true"
}

install_app() {
  mkdir -p "$INSTALL_DIR"

  STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.airtranslate-install.XXXXXX")"

  (
    cd "$SOURCE_DIR"
    ./script/build_and_run.sh --build-only
  )

  [[ -d "$APP_SOURCE" ]] || fail "build completed without producing $APP_SOURCE"
  ditto "$APP_SOURCE" "$STAGING_DIR/$APP_NAME.app"
  codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  wait_for_process_to_stop

  if [[ -e "$APP_TARGET" ]]; then
    mkdir -p "$BACKUP_DIR"
    rm -rf -- "$BACKUP_PATH"
    mv "$APP_TARGET" "$BACKUP_PATH"
    BACKUP_CREATED_THIS_RUN="true"
    echo "Previous app preserved at $BACKUP_PATH"
  fi

  mv "$STAGING_DIR/$APP_NAME.app" "$APP_TARGET"
  SWAP_COMPLETE="true"
  rm -rf -- "$STAGING_DIR"
  STAGING_DIR=""
}

wait_for_process_to_stop() {
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  fail "$APP_NAME did not stop; close it and run the installer again"
}

open_and_verify_app() {
  local attempt
  local pid
  local command

  open "$APP_TARGET"
  for ((attempt = 0; attempt < 50; attempt++)); do
    pid="$(pgrep -n -x "$APP_NAME" || true)"
    if [[ -n "$pid" ]]; then
      command="$(ps -p "$pid" -o command=)"
      [[ "$command" == "$APP_BINARY" ]] || fail "a different AirTranslate build is running: $command"
      return 0
    fi
    sleep 0.2
  done
  fail "AirTranslate was installed but did not open"
}

check_mac

if [[ "$MODE" == "--check" || "$MODE" == "check" ]]; then
  echo "Compatible Mac detected. AirTranslate can be installed for this user."
  exit 0
fi

if [[ "$MODE" != "install" && "$MODE" != "--no-launch" && "$MODE" != "no-launch" ]]; then
  fail "usage: $0 [install|--check|--no-launch]"
fi

acquire_lock
prepare_source
install_app

echo "Installed $APP_TARGET"
echo "Source commit: $(git -C "$SOURCE_DIR" rev-parse HEAD)"

if [[ "$MODE" == "install" ]]; then
  open_and_verify_app
  INSTALL_COMPLETE="true"
  echo "AirTranslate opened. Approve Microphone and Speech Recognition if macOS asks."
  echo "After an update, macOS may ask again if this Mac does not have a persistent signing identity."
else
  INSTALL_COMPLETE="true"
fi
