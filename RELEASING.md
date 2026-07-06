# Releasing (notarized) builds

Focus Browser is distributed as a **notarized** `.zip` so users can download and
open it with no Gatekeeper warnings. This is a maintainer-only guide.

## One-time setup

### 1. Developer ID Application certificate
Notarization requires a **Developer ID Application** certificate (the "Apple
Development" cert used for local builds is *not* sufficient).

- Xcode ▸ **Settings** ▸ **Accounts** ▸ select your Apple ID ▸ **Manage
  Certificates…** ▸ click **+** ▸ **Developer ID Application**.
- Or create it at
  https://developer.apple.com/account/resources/certificates/list
  and double-click the downloaded `.cer` to add it to your keychain.

You must be the team's **Account Holder / Admin** to create this cert.

Verify it landed:
```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. Notary credentials
Create an **app-specific password** at https://account.apple.com ▸ Sign-In &
Security ▸ App-Specific Passwords. Then store a notarytool profile:

```sh
xcrun notarytool store-credentials FocusBrowserNotary \
  --apple-id jeffehobbs@gmail.com \
  --team-id YKF353373Y \
  --password <the-app-specific-password>
```

## Cutting a release

```sh
./release.sh            # builds, signs, notarizes, staples → FocusBrowser.zip
```

Then publish it (bump the version to match `MARKETING_VERSION` in `project.yml`):

```sh
gh release create v1.0 FocusBrowser.zip \
  --title "Focus Browser 1.0" \
  --notes "Switch your default browser automatically based on the active Focus mode."
```

`release.sh` ends with an `spctl` check — a passing "accepted / Notarized
Developer ID" line means the download will open without warnings.
