#!/bin/bash
# Builds Shotwright, signs it with a stable identity, installs it to /Applications and relaunches it.
#
# macOS ties the Screen Recording permission to the app's code signature. An unsigned or ad-hoc
# build gets a new signature on every rebuild, so the permission stops matching and macOS asks
# again even though the switch in System Settings is still on. Signing every build with the same
# certificate keeps the permission across rebuilds.
#
# Identity: $SHOTWRIGHT_SIGN_IDENTITY if set, else the "Developer ID Application" certificate (the
# same one the released DMG uses, so local builds and releases share one permission), else the
# first "Apple Development" certificate, else a self-signed "Shotwright Local Signing" certificate
# created on first run.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME=Shotwright
LOCAL_CERT="Shotwright Local Signing"
DEST="/Applications/$APP_NAME.app"
BUILD_DIR="build"

find_identity() {
    security find-identity -p codesigning 2>/dev/null \
        | grep -m1 -E "\"($1)" | sed -E 's/.*"(.*)"/\1/' || true
}

create_local_cert() {
    echo "No Developer ID or Apple Development certificate found; creating \"$LOCAL_CERT\" in the login keychain."
    local tmp; tmp=$(mktemp -d)
    cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $LOCAL_CERT
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -config "$tmp/cert.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -name "$LOCAL_CERT" -out "$tmp/cert.p12" -passout pass:shotwright
    security import "$tmp/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P shotwright -T /usr/bin/codesign
    rm -rf "$tmp"
}

IDENTITY="${SHOTWRIGHT_SIGN_IDENTITY:-}"
[ -z "$IDENTITY" ] && IDENTITY=$(find_identity "Developer ID Application")
[ -z "$IDENTITY" ] && IDENTITY=$(find_identity "Apple Development")
[ -z "$IDENTITY" ] && IDENTITY=$(find_identity "$LOCAL_CERT")
if [ -z "$IDENTITY" ]; then
    create_local_cert
    IDENTITY="$LOCAL_CERT"
fi
echo "Signing with: $IDENTITY"

xcodegen generate
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO build | tail -n 3

BUILT="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
# Sign nested code (Sparkle) first, then the app with its entitlements.
SPARKLE="$BUILT/Contents/Frameworks/Sparkle.framework"
[ -d "$SPARKLE" ] && codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$SPARKLE"
codesign --force --options runtime --timestamp=none \
    --entitlements "Support/$APP_NAME/$APP_NAME.entitlements" \
    --sign "$IDENTITY" "$BUILT"
codesign --verify --strict "$BUILT"
codesign -d -r- "$BUILT" 2>&1 | grep designated

pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
