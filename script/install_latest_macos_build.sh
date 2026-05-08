#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/glstt-mac-derived}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_NAME="GLSTT.app"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
LAUNCH_AFTER_INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --launch)
            LAUNCH_AFTER_INSTALL=true
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--launch]" >&2
            exit 64
            ;;
    esac
done

cd "$PROJECT_ROOT"

xcodebuild \
    -project GLSTT.xcodeproj \
    -scheme GLSTT \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Expected built app not found at $BUILT_APP" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"

if pgrep -x GLSTT >/dev/null; then
    osascript -e 'tell application "GLSTT" to quit' >/dev/null 2>&1 || true
    sleep 1
    pkill -x GLSTT >/dev/null 2>&1 || true
fi

rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$BUILT_APP" >/dev/null 2>&1 || true

rm -rf "$BUILT_APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALLED_APP"

echo "Installed latest GLSTT build to $INSTALLED_APP"

if [[ "$LAUNCH_AFTER_INSTALL" == true ]]; then
    open -n "$INSTALLED_APP"
fi
