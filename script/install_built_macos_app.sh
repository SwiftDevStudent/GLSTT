#!/bin/zsh
set -euo pipefail

APP_NAME="GLSTT.app"
INSTALL_DIR="${GLSTT_INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"

if [[ -n "${ACTION:-}" && "${ACTION:-}" != "build" ]]; then
    echo "Skipping GLSTT install for ACTION=$ACTION"
    exit 0
fi

if [[ -n "${PLATFORM_NAME:-}" && "${PLATFORM_NAME:-}" != "macosx" ]]; then
    echo "Skipping GLSTT install for PLATFORM_NAME=$PLATFORM_NAME"
    exit 0
fi

if [[ -n "${WRAPPER_NAME:-}" && "${WRAPPER_NAME:-}" != "$APP_NAME" ]]; then
    echo "Skipping GLSTT install for WRAPPER_NAME=$WRAPPER_NAME"
    exit 0
fi

BUILT_APP="${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Expected built app not found at $BUILT_APP" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"

if pgrep -x GLSTT >/dev/null 2>&1; then
    osascript -e 'tell application "GLSTT" to quit' >/dev/null 2>&1 || true
    sleep 1
    pkill -x GLSTT >/dev/null 2>&1 || true
fi

rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$BUILT_APP" >/dev/null 2>&1 || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALLED_APP"

echo "Installed latest GLSTT build to $INSTALLED_APP"
