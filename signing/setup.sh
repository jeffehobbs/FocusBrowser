#!/bin/bash
# One-time setup: create a stable self-signed code-signing identity and import
# it into the login keychain. Signing every build with this identity keeps the
# app's designated requirement constant, so a single Full Disk Access grant
# survives future rebuilds (ad-hoc signing would reset it every build).
set -euo pipefail
cd "$(dirname "$0")"

NAME="FocusBrowser Self-Signed"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Identity '$NAME' already present."
  exit 0
fi

openssl req -x509 -newkey rsa:2048 -keyout fb.key -out fb.crt -days 3650 -nodes \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -inkey fb.key -in fb.crt -out fb.p12 -passout pass:fb -name "$NAME"
security import fb.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P fb -T /usr/bin/codesign
echo "Imported '$NAME'. If codesign later prompts to use the key, click 'Always Allow'."
