#!/bin/sh
# Creates a self-signed "zShot Development" code-signing certificate in the login keychain.
# Builds signed with it keep the same identity, so Screen Recording permission survives rebuilds.
set -eu

NAME="${ZSHOT_SIGN_IDENTITY:-zShot Development}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -F "\"$NAME\"" >/dev/null; then
    echo "\"$NAME\" already exists"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.conf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem"

# -legacy keeps the PKCS#12 readable by macOS security when openssl is 3.x; LibreSSL has no such flag.
PASS="zshot"
if openssl version | grep -q "^OpenSSL 3"; then
    openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout "pass:$PASS"
else
    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout "pass:$PASS"
fi

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo "Created \"$NAME\". The first codesign may ask for keychain access; choose Always Allow."
