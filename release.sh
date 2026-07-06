#!/bin/bash
# Build, Developer ID sign, notarize, and staple FocusBrowser for distribution,
# producing FocusBrowser.zip ready to attach to a GitHub Release.
#
# Prerequisites (one-time — see RELEASING.md):
#   1. A "Developer ID Application" certificate in your keychain.
#   2. A stored notarytool credential profile named $NOTARY_PROFILE:
#        xcrun notarytool store-credentials FocusBrowserNotary \
#          --apple-id you@example.com --team-id XXXXXXXXXX --password <app-specific-pw>
set -euo pipefail
cd "$(dirname "$0")"

NOTARY_PROFILE="${NOTARY_PROFILE:-FocusBrowserNotary}"
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')}"

if [ -z "${SIGN_ID:-}" ]; then
  cat <<'MSG'
ERROR: No "Developer ID Application" certificate found in your keychain.
Create one, then re-run:
  • Xcode ▸ Settings ▸ Accounts ▸ (your Apple ID) ▸ Manage Certificates…
    ▸ click + ▸ "Developer ID Application"
  • or https://developer.apple.com/account/resources/certificates/list
MSG
  exit 1
fi
echo "▸ Signing identity: $SIGN_ID"

echo "▸ Generating project + building Release…"
xcodegen generate
xcodebuild -project FocusBrowser.xcodeproj -scheme FocusBrowser -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | tail -5

APP="build/Build/Products/Release/FocusBrowser.app"

echo "▸ Signing with hardened runtime + secure timestamp…"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

ZIP="FocusBrowser.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to Apple notary service (this can take a minute)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Re-zip the stapled app so the ticket travels with the download.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "▸ Done: $ZIP — notarized, stapled, ready for a GitHub Release."
spctl -a -vvv --type exec "$APP" 2>&1 | sed 's/^/    /' || true
