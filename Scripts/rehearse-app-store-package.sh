#!/bin/bash
# Rebuild and inspect the unsigned public archive used for App Store rehearsal.
# This proves the local package shape. Signing, Apple validation, upload, and
# App Store Connect processing still require the release account and must be
# recorded separately in Docs/PHASE_5_RELEASE_CHECKLIST.md.

set -euo pipefail

cd "$(dirname "$0")/.."

STAMP=$(date +%Y%m%d-%H%M%S)
REHEARSAL_ROOT="${1:-.artifacts/app-store-rehearsal/$STAMP}"
ARCHIVE_PATH="$REHEARSAL_ROOT/Sober.xcarchive"
DERIVED_DATA="$REHEARSAL_ROOT/archive-derived-data"

if [ -e "$REHEARSAL_ROOT" ]; then
  echo "Refusing to reuse an existing rehearsal directory: $REHEARSAL_ROOT"
  exit 1
fi

mkdir -p "$REHEARSAL_ROOT"

echo "==> Regenerating the Xcode project"
PROJECT_HASH_BEFORE=$(shasum -a 256 Sober.xcodeproj/project.pbxproj | awk '{print $1}')
xcodegen generate >/dev/null
PROJECT_HASH_AFTER=$(shasum -a 256 Sober.xcodeproj/project.pbxproj | awk '{print $1}')
if [ "$PROJECT_HASH_BEFORE" != "$PROJECT_HASH_AFTER" ]; then
  echo "Sober.xcodeproj was stale. Review and commit the regenerated project, then rerun." >&2
  exit 1
fi

echo "==> Checking source metadata and the public/internal artifact boundary"
Scripts/check-release-metadata.sh
Scripts/check-public-binary.sh "$REHEARSAL_ROOT/boundary-derived-data"

echo "==> Creating unsigned public device archive"
xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  archive >/dev/null

APP="$ARCHIVE_PATH/Products/Applications/Sober.app"
BINARY="$APP/Sober"
MANIFEST="$APP/PrivacyInfo.xcprivacy"

test -f "$BINARY"
plutil -lint "$APP/Info.plist"
plutil -lint "$MANIFEST"

echo "==> Inspecting archived public app"
for key in NSCameraUsageDescription NSFaceIDUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null
  echo "  ok    present: $key"
done

for key in \
  NSLocationWhenInUseUsageDescription \
  NSLocationAlwaysAndWhenInUseUsageDescription \
  UIBackgroundModes \
  NSAppTransportSecurity \
  SoberGuardianAPIURL \
  CFBundleURLTypes; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null 2>&1; then
    echo "  FAIL  archived public app declares $key"
    exit 1
  fi
  echo "  ok    absent: $key"
done

for copy in \
  "No result is a green light." \
  "Examples only. No data is recorded."; do
  LC_ALL=C grep -a -q -F -- "$copy" "$BINARY"
  echo "  ok    review education is archived: \"$copy\""
done

if [ -d "$APP/Frameworks" ] && [ -n "$(ls -A "$APP/Frameworks" 2>/dev/null)" ]; then
  echo "  FAIL  archived public app embeds frameworks"
  exit 1
fi
echo "  ok    no embedded third-party frameworks"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
CHECKSUM=$(shasum -a 256 "$BINARY" | awk '{print $1}')

cat <<EOF

LOCAL REHEARSAL PASSED
Archive:  $ARCHIVE_PATH
Version:  $VERSION ($BUILD)
SHA-256:  $CHECKSUM

This archive is intentionally unsigned. It has not been validated by Apple,
uploaded, processed by App Store Connect, or installed on a physical device.
Record those gates in Docs/PHASE_5_RELEASE_CHECKLIST.md using the signed release
archive and the founder-owned App Store Connect account.
EOF
