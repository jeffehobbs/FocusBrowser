#!/bin/bash
# Build FocusBrowser.app into ./build and (optionally) install to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Generating Xcode project…"
xcodegen generate

echo "▸ Building…"
xcodebuild \
  -project FocusBrowser.xcodeproj \
  -scheme FocusBrowser \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build | tail -20

APP="build/Build/Products/Release/FocusBrowser.app"

# Re-sign with a stable self-signed identity so the app's designated
# requirement (identifier + certificate leaf) stays constant across rebuilds.
# This lets a one-time Full Disk Access grant survive future rebuilds.
SIGN_IDENTITY="FocusBrowser Self-Signed"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "▸ Signing with stable identity: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
  codesign -dvv "$APP" 2>&1 | grep -i "authority=" | head -1
else
  echo "▸ NOTE: '$SIGN_IDENTITY' not in keychain; leaving ad-hoc signature."
  echo "        (Run signing/setup.sh once to create it — FDA will then persist across rebuilds.)"
fi

echo "▸ Built: $APP"

if [[ "${1:-}" == "install" ]]; then
  DEST="$HOME/Applications"
  echo "▸ Installing to ${DEST} ..."
  mkdir -p "$DEST"
  # Quit any running copy so the bundle can be replaced cleanly.
  osascript -e 'tell application "System Events" to set q to (name of processes) contains "FocusBrowser"' >/dev/null 2>&1 || true
  pkill -f "FocusBrowser.app/Contents/MacOS/FocusBrowser" 2>/dev/null || true
  sleep 1
  rm -rf "$DEST/FocusBrowser.app"
  cp -R "$APP" "$DEST/FocusBrowser.app"
  echo "▸ Installed. Launch with: open $DEST/FocusBrowser.app"
fi
