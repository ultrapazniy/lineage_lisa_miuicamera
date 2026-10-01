#!/usr/bin/env bash
# One-time generation of release signing keys (per https://wiki.lineageos.org/signing_builds).
# Run from anywhere after 'build.sh init sync' (needs development/tools/make_key from the tree).
# Keys are created WITHOUT a password. Keep the directory private and backed up:
# losing it means every future build needs a data wipe or key migration.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/config.sh"

SUBJECT=${SUBJECT:-'/C=US/ST=State/L=City/O=Private/OU=Private/CN=Private/emailAddress=private@localhost'}
MAKE_KEY="$SRC/development/tools/make_key"
[ -x "$MAKE_KEY" ] || { echo "make_key not found: sync the tree first"; exit 1; }

mkdir -p "$KEYS"
chmod 700 "$KEYS"

for cert in bluetooth cyngn-app media networkstack nfc platform releasekey sdk_sandbox shared testcert verity; do
    [ -f "$KEYS/$cert.pk8" ] && { echo "skip $cert (exists)"; continue; }
    echo "" | "$MAKE_KEY" "$KEYS/$cert" "$SUBJECT" || true
    [ -f "$KEYS/$cert.pk8" ] || { echo "failed to create $cert"; exit 1; }
done
ln -sf releasekey.pk8      "$KEYS/testkey.pk8"
ln -sf releasekey.x509.pem "$KEYS/testkey.x509.pem"

# APEX keys must be RSA4096
cp "$MAKE_KEY" "$KEYS/make_key"
sed -i 's|2048|4096|g' "$KEYS/make_key"

for apex in "${APEXES[@]}"; do
    [ -f "$KEYS/$apex.pem" ] && { echo "skip $apex (exists)"; continue; }
    subject="/C=US/ST=State/L=City/O=Private/OU=Private/CN=$apex/emailAddress=private@localhost"
    echo "" | "$KEYS/make_key" "$KEYS/$apex" "$subject" || true
    openssl pkcs8 -in "$KEYS/$apex.pk8" -inform DER -nocrypt -out "$KEYS/$apex.pem"
done

echo
echo "Keys are in $KEYS. BACK THEM UP somewhere safe."
