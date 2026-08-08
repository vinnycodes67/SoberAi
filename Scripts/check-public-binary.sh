#!/bin/bash
#
# Public-build boundary check.
#
# Builds the public `Sober` target in Release and asserts that the shipping
# artifact contains no internal-only route copy, no internal permission keys,
# and no Guardian relay configuration.
#
# This exists because the boundary is a compile-time claim. A `#if
# INTERNAL_BUILD` that someone deletes, or an internal string added to a shared
# view, fails silently — the app still builds and the tests still pass. The only
# reliable evidence is the binary itself.
#
# Usage: Scripts/check-public-binary.sh [derived-data-path]

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

DERIVED_DATA="${1:-$(mktemp -d)/dd}"
APP="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Sober.app"
BINARY="$APP/Sober"
failures=0

fail() {
  echo "  FAIL  $1"
  failures=$((failures + 1))
}

pass() {
  echo "  ok    $1"
}

echo "==> Building public Sober target (Release)"
if ! xcodebuild \
  -project Sober.xcodeproj \
  -scheme Sober \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  build >/dev/null 2>&1; then
  echo "  FAIL  public Release build did not succeed"
  exit 1
fi
pass "public Release build"

if [ ! -f "$BINARY" ]; then
  echo "  FAIL  no binary at $BINARY"
  exit 1
fi

# Route copy that must never reach an App Store binary. These are user-visible
# strings from internal-only surfaces; if one appears, a compile-time gate has
# been removed or a new internal string was added to a view shared by both
# targets.
#
# Every needle must be longer than 15 UTF-8 bytes. Swift stores shorter strings
# inline in instructions rather than in the literal section, so `strings` cannot
# see them and the check would pass even when the route is present. The control
# pass below enforces this rather than trusting the author to remember it.
echo
echo "==> Forbidden strings in public Release binary"
FORBIDDEN=(
  "Explore founder demo"
  "Founder result previews remain available from the home screen."
  "Consent, local sessions, export, and deletion"
  "Preview concerning result"
  "Preview inconclusive result"
  "Preview no-signals result"
  # ASCII substring only: the full sentence contains a "·" that does not survive
  # a literal grep against the binary, which the sensitivity control caught.
  "this sample is not uploaded or presented as a real person"
  "Right now the map updates only while Sober is open."
  "Help requests say only that help is needed"
)

for needle in "${FORBIDDEN[@]}"; do
  count=$(strings -a "$BINARY" | grep -c -F -- "$needle")
  if [ "$count" -ne 0 ]; then
    fail "found ${count}x: \"$needle\""
  else
    pass "absent: \"$needle\""
  fi
done

# Internal-only Info.plist keys. Shipping an unused permission string or
# background mode is an App Review rejection trigger and widens the App Privacy
# answers to cover a capability the public app does not have.
echo
echo "==> Forbidden Info.plist keys in public app"
FORBIDDEN_KEYS=(
  NSLocationWhenInUseUsageDescription
  NSLocationAlwaysAndWhenInUseUsageDescription
  UIBackgroundModes
  NSAppTransportSecurity
  SoberGuardianAPIURL
)

for key in "${FORBIDDEN_KEYS[@]}"; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null 2>&1; then
    fail "Info.plist declares $key"
  else
    pass "absent: $key"
  fi
done

# Required keys. The public app still needs camera access, and losing this
# string would crash the check on first use rather than degrade it.
echo
echo "==> Required Info.plist keys"
if /usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$APP/Info.plist" >/dev/null 2>&1; then
  pass "present: NSCameraUsageDescription"
else
  fail "Info.plist is missing NSCameraUsageDescription"
fi

# Sensitivity control.
#
# An "absent" result only means something if the needle would have been found
# had it been there. Three needles in the first version of this script were
# undetectable at any size — they never appeared even in the internal binary
# that definitely contains those routes — so they silently passed forever.
#
# Building the internal target and asserting each needle IS present proves the
# check can fail. A needle that goes missing here is a broken check, not a
# clean build.
echo
echo "==> Sensitivity control (internal target must contain every needle)"
INTERNAL_DD="$DERIVED_DATA-internal"
INTERNAL_BINARY="$INTERNAL_DD/Build/Products/Release-iphonesimulator/SoberInternal.app/SoberInternal"

if xcodebuild \
  -project Sober.xcodeproj \
  -scheme SoberInternal \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$INTERNAL_DD" \
  build >/dev/null 2>&1 && [ -f "$INTERNAL_BINARY" ]; then
  for needle in "${FORBIDDEN[@]}"; do
    count=$(strings -a "$INTERNAL_BINARY" | grep -c -F -- "$needle")
    if [ "$count" -eq 0 ]; then
      fail "needle is undetectable, so the public check is meaningless: \"$needle\""
    else
      pass "detectable (${count}x internally): \"$needle\""
    fi
  done
else
  fail "could not build SoberInternal; forbidden-string sensitivity is unproven"
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "FAILED: $failures public-boundary violation(s)"
  exit 1
fi

echo "PASSED: public build exposes no internal routes, permissions, or relay configuration"
