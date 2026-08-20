#!/bin/bash
# Static release metadata, license, and repository secret gate.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

failures=0

fail() {
  echo "  FAIL  $1"
  failures=$((failures + 1))
}

pass() {
  echo "  ok    $1"
}

MANIFEST="Sober/PrivacyInfo.xcprivacy"

echo "==> Export compliance"
for info_plist in Sober/Info.plist Sober/Info-Internal.plist; do
  if [ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_plist" 2>/dev/null)" = "false" ]; then
    pass "$info_plist declares exempt encryption usage"
  else
    fail "$info_plist must declare ITSAppUsesNonExemptEncryption=false"
  fi
done

echo "==> Privacy manifest"
if plutil -lint "$MANIFEST" >/dev/null 2>&1; then
  pass "PrivacyInfo.xcprivacy is valid"
else
  fail "PrivacyInfo.xcprivacy is not a valid property list"
fi

tracking=$(/usr/libexec/PlistBuddy -c "Print :NSPrivacyTracking" "$MANIFEST" 2>/dev/null || true)
if [ "$tracking" = "false" ]; then
  pass "tracking is declared false"
else
  fail "tracking must be declared false"
fi

manifest_json=$(plutil -convert json -o - "$MANIFEST" 2>/dev/null || true)
for value in \
  NSPrivacyAccessedAPICategoryUserDefaults \
  CA92.1 \
  NSPrivacyAccessedAPICategorySystemBootTime \
  35F9.1; do
  if grep -q -F -- "$value" <<< "$manifest_json"; then
    pass "manifest declares $value"
  else
    fail "manifest is missing $value"
  fi
done

if grep -q -F -- '"NSPrivacyCollectedDataTypes":[]' <<< "$manifest_json"; then
  pass "no collected-data categories are declared"
else
  fail "public v1 manifest must declare an empty collected-data array"
fi

if grep -q -F -- '"NSPrivacyTrackingDomains":[]' <<< "$manifest_json"; then
  pass "no tracking domains are declared"
else
  fail "public v1 manifest must declare an empty tracking-domain array"
fi

echo
echo "==> Public privacy URLs"
SUPPORT_URL="https://vinnycodes67.github.io/SoberSupport/"
PRIVACY_URL="https://vinnycodes67.github.io/SoberSupport/privacy.html"
if grep -q -F -- "$PRIVACY_URL" Sober/Features/Settings/SettingsView.swift; then
  pass "the in-app policy links to the hosted privacy policy"
else
  fail "the in-app policy must link to $PRIVACY_URL"
fi

if grep -q -F -- 'href="privacy.html"' SupportSite/index.html \
  && grep -q -F -- 'href="index.html"' SupportSite/privacy.html; then
  pass "support and privacy pages link to each other"
else
  fail "support and privacy pages must remain mutually reachable"
fi

if grep -q -F -- "Support URL: \`$SUPPORT_URL\`" SupportSite/README.md \
  && grep -q -F -- "Privacy Policy URL: \`$PRIVACY_URL\`" SupportSite/README.md; then
  pass "deployment documentation records both App Store URLs"
else
  fail "SupportSite/README.md must record the live App Store URLs"
fi

echo
echo "==> Third-party asset license"
FONT_LICENSE="Sober/Resources/Fonts/Satoshi-LICENSE.txt"
if [ -s "$FONT_LICENSE" ]; then
  pass "Satoshi license is present"
else
  fail "Satoshi license is missing or empty"
fi

for font in Satoshi-Regular.otf Satoshi-Medium.otf Satoshi-Bold.otf; do
  if [ -s "Sober/Resources/Fonts/$font" ]; then
    pass "$font is present"
  else
    fail "$font is missing or empty"
  fi
done

echo
echo "==> Repository secret scan"
# Keep the scanner's own signatures out of its input, otherwise the rule text
# is indistinguishable from a credential. Generated build products and local
# configuration are already excluded by .gitignore.
secret_pattern='-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk_live_[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9-]{12,}'
secret_hits=$(
  git ls-files -co --exclude-standard -z \
    | while IFS= read -r -d '' file; do
        [ "$file" = "Scripts/check-release-metadata.sh" ] && continue
        printf '%s\0' "$file"
      done \
    | xargs -0 grep -I -n -E -- "$secret_pattern" 2>/dev/null \
    || true
)
if [ -n "$secret_hits" ]; then
  printf '%s\n' "$secret_hits"
  fail "credential-like content was found"
else
  pass "no private-key or production-token signatures found"
fi

echo
echo "==> Developer tooling safety"
unsafe_checkpoint_loads=$(grep -R -n -E \
  'torch\.load\([^[:cntrl:]]*weights_only[[:space:]]*=[[:space:]]*False' \
  --include='*.py' Training/PupilSegmentation 2>/dev/null || true)
if [ -n "$unsafe_checkpoint_loads" ]; then
  printf '%s\n' "$unsafe_checkpoint_loads"
  fail "PyTorch checkpoints must not enable executable pickle deserialization"
else
  pass "PyTorch checkpoint loads keep executable pickle deserialization disabled"
fi

echo
echo "==> Deferred Guardian backend"
if grep -q -E '^GUARDIAN_FOUNDER_MODE[[:space:]]*=[[:space:]]*"false"[[:space:]]*$' \
  Backend/wrangler.toml; then
  pass "checked-in Guardian deployment fails closed"
else
  fail "Backend/wrangler.toml must keep GUARDIAN_FOUNDER_MODE=false"
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "FAILED: $failures release-metadata violation(s)"
  exit 1
fi

echo "PASSED: privacy declarations, licenses, and repository secret scan"
