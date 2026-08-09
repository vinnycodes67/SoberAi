#!/bin/bash
# Runs the core UI evidence suite on a compact phone and the accessibility
# layout suite on a large phone. Screenshot attachments are retained in each
# result bundle.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

simulators=$(Scripts/prepare-ui-simulators.sh)
small_udid=$(printf '%s\n' "$simulators" | awk -F= '/^SOBER_SMALL_UDID=/{print $2}')
large_udid=$(printf '%s\n' "$simulators" | awk -F= '/^SOBER_LARGE_UDID=/{print $2}')

if [ -z "$small_udid" ] || [ -z "$large_udid" ]; then
  echo "Simulator preparation did not return both UDIDs" >&2
  exit 1
fi

mkdir -p .artifacts/ui-tests
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
small_result="$PWD/.artifacts/ui-tests/small-$run_id.xcresult"
large_result="$PWD/.artifacts/ui-tests/large-accessibility-$run_id.xcresult"

xcrun simctl boot "$small_udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$small_udid" -b

echo "==> Compact-device UI suite"
xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$small_udid" \
  -resultBundlePath "$small_result" \
  -quiet \
  test \
  -only-testing:SoberUITests/SoberUITests

xcrun simctl boot "$large_udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$large_udid" -b

echo "==> Large-device accessibility UI suite"
xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$large_udid" \
  -resultBundlePath "$large_result" \
  -quiet \
  test \
  -only-testing:SoberUITests/SoberAccessibilityUITests

echo "UI evidence bundles:"
echo "  $small_result"
echo "  $large_result"
