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

# Hosted macOS runners are small. On them an app launch can take 90 s, and
# XCUITest's accessibility snapshots time out against a simulator that is
# still doing first-boot work, so single tests used to run out their 2-minute
# allowance on 30-second existence checks while passing in seconds locally.
# Three things keep that from failing the job without hiding real failures:
#
# - one simulator at a time: two booted together starve the runner;
# - a longer allowance per test, so a slow launch is not a failure;
# - one retry of a failed test. A real failure fails both attempts, and the
#   result bundle records any test that only passed on retry.
xcrun simctl boot "$small_udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$small_udid" -b

# Runs one suite. If the simulator itself has gone (xcodebuild exit 70, "Unable
# to find a device"), it is an infrastructure fault rather than a test result:
# boot it again and retry once. Test failures are never retried.
run_suite() {
  local udid="$1" result="$2"
  shift 2
  local status=0
  xcodebuild_suite "$udid" "$result" "$@" || status=$?
  if [ "$status" -eq 70 ]; then
    echo "Simulator $udid was unavailable; rebooting and retrying once" >&2
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b
    rm -rf "$result"
    status=0
    xcodebuild_suite "$udid" "$result" "$@" || status=$?
  fi
  return "$status"
}

xcodebuild_suite() {
  local udid="$1" result="$2"
  shift 2
  xcodebuild \
    -project Sober.xcodeproj \
    -scheme Sober \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" \
    -resultBundlePath "$result" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 300 \
    -retry-tests-on-failure \
    -test-iterations 2 \
    -quiet \
    test \
    "$@"
}

echo "==> Compact-device UI suite"
run_suite "$small_udid" "$small_result" \
  -only-testing:SoberUITests/JourneySmokeUITests \
  -only-testing:SoberUITests/PublicBoundaryUITests \
  -only-testing:SoberUITests/SoberUITests

xcrun simctl shutdown "$small_udid" >/dev/null 2>&1 || true
xcrun simctl boot "$large_udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$large_udid" -b

echo "==> Large-device accessibility UI suite"
run_suite "$large_udid" "$large_result" \
  -only-testing:SoberUITests/AccessibilityUITests \
  -only-testing:SoberUITests/SoberAccessibilityUITests

echo "UI evidence bundles:"
echo "  $small_result"
echo "  $large_result"
