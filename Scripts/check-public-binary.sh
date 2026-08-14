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

echo "==> Source release metadata"
if Scripts/check-release-metadata.sh; then
  pass "source release metadata"
else
  fail "source release metadata"
fi

# Result privacy is a source-level invariant as well as an archive invariant.
# External URL actions remain valid because they power Ride, Call, and Message;
# portable result mechanisms do not belong on the result surface.
echo "==> Result non-sharing source gate"
RESULT_SOURCE="Sober/DesignKit/Screens/DSIntegratedResultScreen.swift"
RESULT_FORBIDDEN=(
  ShareLink
  UIActivityViewController
  Transferable
  fileExporter
  ResultReceipt
  AuthenticatedResult
)
for needle in "${RESULT_FORBIDDEN[@]}"; do
  if grep -q -F -- "$needle" "$RESULT_SOURCE"; then
    fail "result surface contains portable-proof mechanism: $needle"
  else
    pass "result surface omits: $needle"
  fi
done

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

# Public-facing beta/prototype language makes a finished App Store build look
# incomplete under Guideline 2.1. Internal tooling may still use those labels.
PUBLIC_COPY_FORBIDDEN=(
  "Prototype consent only"
  "This prototype screens for changes"
  "Prototype measurements explain what contributed"
  "This MVP is not clinically validated"
  "Reset prototype"
  "We saw signs consistent with impairment"
  "We didn’t detect signals. This does not mean you’re sober"
  "-sober-ui-testing"
  "-sober-baseline-sessions"
)
for needle in "${PUBLIC_COPY_FORBIDDEN[@]}"; do
  if LC_ALL=C grep -a -q -F -- "$needle" "$BINARY"; then
    fail "public-facing pre-release copy remains: \"$needle\""
  else
    pass "absent pre-release copy: \"$needle\""
  fi
done

PUBLIC_RESULT_COPY_REQUIRED=(
  "This check found changes outside your usual range. Don’t drive."
  "This check did not find changes. It cannot establish sobriety or driving safety."
  "You reported recent use"
  "You reported drinking or using something in the last 4 hours. No tasks were needed. Don’t drive."
)
for needle in "${PUBLIC_RESULT_COPY_REQUIRED[@]}"; do
  # Scan the binary directly. `strings | grep -q` is unsafe with `pipefail`:
  # once grep finds a match and exits, strings can receive SIGPIPE and make the
  # successful lookup report status 141. Direct grep also preserves UTF-8 copy
  # such as the curly apostrophe in "Don't drive."
  if LC_ALL=C grep -a -q -F -- "$needle" "$BINARY"; then
    pass "required bounded result copy: \"$needle\""
  else
    fail "required bounded result copy is missing: \"$needle\""
  fi
done

echo
echo "==> Experimental model boundary"
PUBLIC_MODEL=$(find "$APP" \( -name 'PupilSegmentation.mlmodelc' -o -name 'PupilSegmentation.mlpackage' \) -print -quit)
if [ -n "$PUBLIC_MODEL" ]; then
  fail "public app bundles the unvalidated pupil-segmentation model"
else
  pass "public app omits the unvalidated pupil-segmentation model"
fi

echo
echo "==> Required coercion-resistant result copy"
RESULT_PRIVACY_COPY="This result is private context for you. It is not evidence for a parent, partner, employer, school, insurer, or authority."
result_privacy_copy_count=$(strings -a "$BINARY" | grep -c -F -- "$RESULT_PRIVACY_COPY")
if [ "$result_privacy_copy_count" -gt 0 ]; then
  pass "public result explains that it is not portable evidence"
else
  fail "public result is missing the required private-context boundary"
fi

echo
echo "==> Public App Review education path"
REVIEW_PATH_COPY=(
  "No result is a green light."
  "Examples only. No data is recorded."
  "Opening this page does not use the camera, run the scorer, add to History, or count toward your baseline."
)
for needle in "${REVIEW_PATH_COPY[@]}"; do
  count=$(strings -a "$BINARY" | grep -c -F -- "$needle")
  if [ "$count" -gt 0 ]; then
    pass "review education is present: \"$needle\""
  else
    fail "public Release binary is missing review education: \"$needle\""
  fi
done

# The examples must remain an inert explanation. This source gate complements
# the journey test that proves opening and closing the sheet leaves both the
# baseline and History empty.
REVIEW_PATH_SOURCE="Sober/Features/Home/HowResultsWorkView.swift"
REVIEW_PATH_FORBIDDEN=(
  "@EnvironmentObject"
  "ScreeningFlowView("
  "AppModel("
  "ScreeningEngine("
)
for needle in "${REVIEW_PATH_FORBIDDEN[@]}"; do
  if grep -q -F -- "$needle" "$REVIEW_PATH_SOURCE"; then
    fail "review education gained an active screening dependency: $needle"
  else
    pass "review education omits active dependency: $needle"
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
  CFBundleURLTypes
)

for key in "${FORBIDDEN_KEYS[@]}"; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null 2>&1; then
    fail "Info.plist declares $key"
  else
    pass "absent: $key"
  fi
done

# Required keys. Losing either usage string can make the corresponding system
# permission fail on a physical device rather than degrade gracefully.
echo
echo "==> Required Info.plist keys"
REQUIRED_KEYS=(NSCameraUsageDescription NSFaceIDUsageDescription)
for key in "${REQUIRED_KEYS[@]}"; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null 2>&1; then
    pass "present: $key"
  else
    fail "Info.plist is missing $key"
  fi
done

echo
echo "==> Bundled privacy manifest"
PRIVACY_MANIFEST="$APP/PrivacyInfo.xcprivacy"
if [ -f "$PRIVACY_MANIFEST" ] && plutil -lint "$PRIVACY_MANIFEST" >/dev/null 2>&1; then
  pass "public app contains a valid PrivacyInfo.xcprivacy"
  privacy_json=$(plutil -convert json -o - "$PRIVACY_MANIFEST" 2>/dev/null || true)
  for value in \
    NSPrivacyAccessedAPICategoryUserDefaults \
    CA92.1 \
    NSPrivacyAccessedAPICategorySystemBootTime \
    35F9.1; do
    if grep -q -F -- "$value" <<< "$privacy_json"; then
      pass "bundled manifest declares $value"
    else
      fail "bundled manifest is missing $value"
    fi
  done
else
  fail "public app is missing a valid PrivacyInfo.xcprivacy"
fi

# Submission reconciliation.
#
# Every App Store answer has to be true of the artifact, not of the plan. These
# check the answers that can be derived from the bundle and binary.
echo
echo "==> App Store answers vs the artifact"
tracking=$(/usr/libexec/PlistBuddy -c "Print :NSPrivacyTracking" "$PRIVACY_MANIFEST" 2>/dev/null || true)
if [ "$tracking" = "false" ]; then
  pass "manifest declares no tracking"
else
  fail "manifest does not declare tracking false"
fi

if /usr/libexec/PlistBuddy -c "Print :NSPrivacyCollectedDataTypes:0" "$PRIVACY_MANIFEST" >/dev/null 2>&1; then
  fail "manifest declares collected data; App Privacy answers must be updated"
else
  pass "manifest declares no collected data"
fi

if [ -d "$APP/Frameworks" ] && [ -n "$(ls -A "$APP/Frameworks" 2>/dev/null)" ]; then
  fail "app embeds frameworks: $(ls "$APP/Frameworks" | tr '\n' ' ')"
else
  pass "no embedded third-party frameworks"
fi

category=$(/usr/libexec/PlistBuddy -c "Print :LSApplicationCategoryType" "$APP/Info.plist" 2>/dev/null || true)
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist" 2>/dev/null || true)
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist" 2>/dev/null || true)
echo "  note  category is ${category:-unset}"
echo "  note  version ${version:-unset} (${build:-unset})"
echo "  note  export compliance must be answered for the archived binary"

# The public v1 intentionally ships with no crash or analytics provider. Check
# the linked image and embedded frameworks rather than relying on package files
# alone, because a manually embedded binary would otherwise bypass the audit.
echo
echo "==> No-provider telemetry audit"
FORBIDDEN_PROVIDER_SIGNATURES=(
  "Firebase|FIRApp"
  "Crashlytics|FirebaseCrashlytics"
  "Sentry|SentrySDK"
  "PostHog|PostHogSDK"
  "Mixpanel|MixpanelInstance"
  "Amplitude|AmplitudeSwift"
  "Datadog|DatadogCore"
  "NewRelic|NewRelicAgent"
  "Instabug|InstabugSDK"
  "Bugsnag|BugsnagClient"
  "AppCenter|MSACAppCenter"
)

LINKED_IMAGE=$(otool -L "$BINARY" 2>/dev/null || true)
BUNDLED_FRAMEWORKS=$(find "$APP" -path '*/Frameworks/*' -print 2>/dev/null || true)
for entry in "${FORBIDDEN_PROVIDER_SIGNATURES[@]}"; do
  provider=${entry%%|*}
  binary_signature=${entry#*|}
  # Framework names can use the readable provider name. Binary scans need a
  # provider-specific symbol: a bare term such as "Amplitude" also describes
  # the app's pupil-response measurement and is not telemetry evidence.
  if grep -qi -F -- "$provider" <<< "$LINKED_IMAGE"$'\n'"$BUNDLED_FRAMEWORKS" \
    || LC_ALL=C grep -a -q -F -- "$binary_signature" "$BINARY"; then
    fail "telemetry provider is linked or embedded: $provider"
  else
    pass "no provider artifact: $provider"
  fi
done

# Public v1 has no push or remote-notification contract. The simulator product
# may be unsigned; when entitlements are present, assert the deferred keys are
# absent from the signed payload as well.
ENTITLEMENTS=$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)
for key in aps-environment com.apple.developer.usernotifications.communication; do
  if grep -q -F -- "$key" <<< "$ENTITLEMENTS"; then
    fail "public app contains deferred entitlement: $key"
  else
    pass "absent entitlement: $key"
  fi
done

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
INTERNAL_PRIVACY_MANIFEST="$INTERNAL_DD/Build/Products/Release-iphonesimulator/SoberInternal.app/PrivacyInfo.xcprivacy"

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
  if [ -f "$INTERNAL_PRIVACY_MANIFEST" ] \
    && plutil -lint "$INTERNAL_PRIVACY_MANIFEST" >/dev/null 2>&1; then
    pass "internal app also contains the privacy manifest"
  else
    fail "internal app is missing a valid PrivacyInfo.xcprivacy"
  fi
  INTERNAL_MODEL=$(find "$(dirname "$INTERNAL_BINARY")" -name 'PupilSegmentation.mlmodelc' -print -quit)
  if [ -n "$INTERNAL_MODEL" ]; then
    pass "experimental pupil model remains available in SoberInternal"
  else
    fail "SoberInternal is missing its experimental pupil model"
  fi
else
  fail "could not build SoberInternal; forbidden-string sensitivity is unproven"
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "FAILED: $failures public-boundary violation(s)"
  exit 1
fi

echo "PASSED: public build exposes no internal routes, permissions, relay configuration, or telemetry provider"
