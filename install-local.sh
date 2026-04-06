#!/bin/bash
# Build VoiceInk from source and install it to /Applications, replacing any existing copy.
# Usage: ./install-local.sh
#
# This is a local convenience wrapper around `make local`. Not part of upstream.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="VoiceInkNeo"
BUILT_APP="$REPO_ROOT/.local-build/Build/Products/Debug/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

cd "$REPO_ROOT"

echo "==> Building (make local)"
make local

if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: Build succeeded but $BUILT_APP not found."
    exit 1
fi

echo
echo "==> Quitting any running ${APP_NAME}"
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
# Give it a moment, then force-kill if still around
sleep 1
pkill -x "${APP_NAME}" 2>/dev/null || true

echo
echo "==> Installing to $DEST"
if [ -d "$DEST" ]; then
    if ! rm -rf "$DEST" 2>/dev/null; then
        echo "   (needs sudo to remove existing $DEST)"
        sudo rm -rf "$DEST"
    fi
fi

if ! ditto "$BUILT_APP" "$DEST" 2>/dev/null; then
    echo "   (needs sudo to write to /Applications)"
    sudo ditto "$BUILT_APP" "$DEST"
fi

# Strip quarantine so Gatekeeper doesn't complain about the ad-hoc-signed build
xattr -cr "$DEST" 2>/dev/null || sudo xattr -cr "$DEST"

# Remove the ~/Downloads copy the Makefile dropped, since we don't want two copies lying around
rm -rf "$HOME/Downloads/${APP_NAME}.app"

# Ad-hoc signatures churn on every rebuild, so TCC grants get invalidated even
# though System Settings still shows the toggle ON. Wipe the stale rows so the
# user can cleanly re-add the new build in Privacy & Security.
BUNDLE_ID="com.prakashjoshipax.VoiceInkNeo"
echo
echo "==> Resetting stale TCC grants for $BUNDLE_ID"
tccutil reset Accessibility  "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent    "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Microphone     "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture  "$BUNDLE_ID" 2>/dev/null || true
tccutil reset AppleEvents    "$BUNDLE_ID" 2>/dev/null || true

echo
echo "==> Done. Installed: $DEST"
echo "    Launch: open \"$DEST\""
echo
echo "    First paste after rebuild won't work until you re-add the app to"
echo "    Privacy & Security → Accessibility (and Input Monitoring for hotkeys)."
echo "    Quick jump: open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
