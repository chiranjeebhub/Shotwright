#!/bin/bash
# Builds the direct-download release of Shotwright: Developer ID signed, notarized and stapled,
# packed in a DMG, and added to the Sparkle update feed.
#
#   SHOTWRIGHT_TEAM_ID=ABCDE12345 scripts/release-direct.sh
#
# One-time setup on this Mac (see README > Direct download):
#   - a "Developer ID Application" certificate for your team (Xcode > Settings > Accounts > Manage Certificates)
#   - notarization credentials saved as a keychain profile:
#       xcrun notarytool store-credentials shotwright-notary --apple-id you@example.com --team-id ABCDE12345
#   - the Sparkle signing key in your keychain (generate_keys), its public half in project.yml (SPARKLE_PUBLIC_KEY)
#
# Output: dist/Shotwright-<version>.dmg, and a new entry at the top of appcast.xml pointing at the
# GitHub release v<version>. Bump MARKETING_VERSION in project.yml before each release.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME=Shotwright
SCHEME=Shotwright
WORK="build/Direct"
DIST="dist"
ARCHIVE="$WORK/$APP_NAME.xcarchive"
PACKAGES="build/SourcePackages"
RELEASES_URL="https://github.com/chiranjeebhub/Shotwright/releases"
NOTARY_PROFILE="${SHOTWRIGHT_NOTARY_PROFILE:-shotwright-notary}"

: "${SHOTWRIGHT_TEAM_ID:?Set SHOTWRIGHT_TEAM_ID to your 10-character Team ID (developer.apple.com > Account > Membership details)}"
BUILD_NUMBER=$(date -u +%Y%m%d%H%M)

notarize() {
    echo "Notarizing $(basename "$1")…"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait | tail -n 2
}

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"
xcodegen generate

echo "Archiving build $BUILD_NUMBER…"
xcodebuild archive -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    -clonedSourcePackagesDirPath "$PACKAGES" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$SHOTWRIGHT_TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" | tail -n 3

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$SHOTWRIGHT_TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/export" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates | tail -n 3

APP="$WORK/export/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
for key in SUFeedURL SUPublicEDKey; do
    value=$(/usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist" 2>/dev/null || true)
    [ -n "$value" ] || { echo "$key is empty: set SPARKLE_FEED_URL and SPARKLE_PUBLIC_KEY in project.yml"; exit 1; }
done
codesign --verify --strict --deep "$APP"

# Notarize and staple the app itself, so it opens offline once dragged out of the DMG.
ditto -c -k --keepParent "$APP" "$WORK/$APP_NAME.zip"
notarize "$WORK/$APP_NAME.zip"
xcrun stapler staple "$APP"

DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGING="$WORK/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application.*($SHOTWRIGHT_TEAM_ID)" | sed -E 's/.*"(.*)"/\1/')
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

# Sign the DMG for Sparkle (EdDSA key from the keychain) and add it to the top of appcast.xml.
SIGN_UPDATE=$(find "$PACKAGES" -path "*Sparkle*/bin/sign_update" -type f | head -n 1)
SIGNATURE=$("$SIGN_UPDATE" "$DMG")
URL="$RELEASES_URL/download/v$VERSION/$(basename "$DMG")"
ITEM=$(cat <<XML
        <item>
            <title>Version $VERSION</title>
            <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="$URL" type="application/octet-stream" $SIGNATURE/>
        </item>
XML
)
ITEM="$ITEM" perl -0pi -e 's/(<!-- New releases go below this line\. -->\n)/$1$ENV{ITEM}\n/' appcast.xml

echo
echo "Built $APP_NAME $VERSION (build $BUILD_NUMBER): $DMG"
echo "To publish:"
echo "  1. gh release create v$VERSION \"$DMG\" --repo chiranjeebhub/Shotwright --title \"Shotwright $VERSION\""
echo "     (or upload it on $RELEASES_URL/new with tag v$VERSION)"
echo "  2. git commit appcast.xml -m \"Release $VERSION\" && git push"
