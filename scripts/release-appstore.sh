#!/bin/bash
# Archives Shotwright for the Mac App Store and exports a signed .pkg, or uploads it to
# App Store Connect.
#
#   SHOTWRIGHT_TEAM_ID=ABCDE12345 scripts/release-appstore.sh           # export build/AppStore/Shotwright.pkg
#   SHOTWRIGHT_TEAM_ID=ABCDE12345 scripts/release-appstore.sh --upload  # upload to App Store Connect
#
# Needs: a paid Apple Developer Program team, your Apple ID added in Xcode > Settings > Accounts,
# and the app record for com.shotwright.app in App Store Connect. Xcode creates the distribution
# certificates and provisioning profile itself (-allowProvisioningUpdates).
#
# The version shown in the store is MARKETING_VERSION in project.yml. The build number is the
# current UTC time (yyyyMMddHHmm), so every upload has a higher one than the last.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME=Shotwright
OUT="build/AppStore"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
DESTINATION=export
[ "${1:-}" = "--upload" ] && DESTINATION=upload

: "${SHOTWRIGHT_TEAM_ID:?Set SHOTWRIGHT_TEAM_ID to your 10-character Team ID (developer.apple.com > Account > Membership details)}"
export SHOTWRIGHT_TEAM_ID
BUILD_NUMBER=$(date -u +%Y%m%d%H%M)

rm -rf "$OUT"
mkdir -p "$OUT"
xcodegen generate

echo "Archiving build $BUILD_NUMBER…"
xcodebuild archive -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$SHOTWRIGHT_TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" | tail -n 3

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>$SHOTWRIGHT_TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates | tail -n 3

if [ "$DESTINATION" = upload ]; then
    echo "Uploaded build $BUILD_NUMBER. It appears in App Store Connect > TestFlight after processing (10 to 30 minutes)."
else
    echo "Exported $OUT/$APP_NAME.pkg (build $BUILD_NUMBER). Upload it with Transporter, or rerun with --upload."
fi
