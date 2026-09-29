#!/bin/bash
# Sign, archive, validate and upload the public Sober build to TestFlight.
#
# Scripts/rehearse-app-store-package.sh proves the package shape with no
# account. This script is the step after it, and it cannot run without App
# Store Connect credentials. Nothing here substitutes for recording the result
# in Docs/PHASE_5_RELEASE_CHECKLIST.md.
#
# Needs an App Store Connect API key (App Store Connect → Users and Access →
# Integrations → App Store Connect API, role "App Manager" or higher):
#
#   export ASC_KEY_ID=XXXXXXXXXX          # the key's Key ID
#   export ASC_ISSUER_ID=xxxxxxxx-....    # the issuer UUID, shown above the key list
#   export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
#
# The .p8 downloads exactly once. Keep it out of this repository — the secret
# scan in check-release-metadata.sh fails the build if it lands here.

set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID — see the header of this script}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID — see the header of this script}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH — see the header of this script}"

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "No API key at $ASC_KEY_PATH" >&2
  exit 1
fi

TEAM_ID="CPRVLR97XJ"
STAMP=$(date +%Y%m%d-%H%M%S)
ROOT=".artifacts/testflight/$STAMP"
ARCHIVE="$ROOT/Sober.xcarchive"
EXPORT="$ROOT/export"

mkdir -p "$EXPORT"

AUTH=(
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

echo "==> Regenerating the Xcode project"
xcodegen generate >/dev/null

VERSION=$(awk '/MARKETING_VERSION/ {gsub(/"/, "", $2); print $2; exit}' project.yml)
BUILD=$(awk '/CURRENT_PROJECT_VERSION/ {gsub(/"/, "", $2); print $2; exit}' project.yml)
echo "    candidate: $VERSION ($BUILD)"
echo "    App Store Connect rejects a build number it has already seen."

echo "==> Proving the package shape before spending an upload"
Scripts/check-release-metadata.sh >/dev/null
Scripts/check-public-binary.sh "$ROOT/boundary-derived-data" >/dev/null
echo "    ok    metadata and public/internal boundary"

echo "==> Archiving the public Sober scheme (Release, signed)"
xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

echo "==> Confirming the archive declares nothing it should not"
APP="$ARCHIVE/Products/Applications/Sober.app"
for key in \
  NSLocationWhenInUseUsageDescription \
  NSLocationAlwaysAndWhenInUseUsageDescription \
  UIBackgroundModes \
  SoberGuardianAPIURL; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null 2>&1; then
    echo "  FAIL  signed archive declares $key" >&2
    exit 1
  fi
done
echo "  ok    no location, background mode, or Guardian endpoint"
echo "  archive SHA-256: $(shasum -a 256 "$APP/Sober" | awk '{print $1}')"

cat > "$ROOT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "==> Validating and uploading to App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/ExportOptions.plist" \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  "${AUTH[@]}"

echo
echo "Uploaded $VERSION ($BUILD). Artifacts in $ROOT"
echo "App Store Connect still has to finish processing before the build reaches"
echo "TestFlight. Record the processed-build link in"
echo "Docs/PHASE_5_RELEASE_CHECKLIST.md."
