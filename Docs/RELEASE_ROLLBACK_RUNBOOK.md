# Public v1 Release and Rollback Runbook

Public v1 is a client-only release. No backend, remote flag, Guardian relay,
location service, notification service, or analytics provider is required to
launch, check, interpret a result, or open a get-home action.

## Release candidate gate

From a clean checkout of the candidate commit:

```bash
xcodegen generate
Scripts/check-release-metadata.sh
xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:SoberTests
Scripts/run-ui-tests.sh
npm test --prefix Backend
Scripts/check-public-binary.sh
plutil -lint Sober/Info.plist Sober/Info-Internal.plist Sober/PrivacyInfo.xcprivacy
git diff --check
git diff --exit-code
```

Retain the commit, build number, Xcode version, both UI `.xcresult` bundles,
public/internal Release gate output, and named reviewer. Backend tests preserve
the isolated v1.1 contract; they are not a public-v1 runtime dependency.

## Stop-ship triggers

Pause TestFlight or phased rollout immediately for any of these:

- false baseline readiness or recreated synthetic sessions;
- missing/unmeasured data shown as normal, clear, or completed;
- reported use capable of producing a no-signals result;
- a result share/export/deep-link/attestation path or missing anti-coercion copy;
- raw camera/biometric data persistence or any sensitive telemetry disclosure;
- destructive migration, deletion reported as successful when bytes remain, or
  quarantine restored as measured truth;
- public archive containing Guardian, Circle, Research/founder routes, location,
  notification, local-network, URL-scheme, or relay configuration.

## Decision and rollback

1. Name one incident lead and freeze submission/rollout. Preserve the affected
   build and evidence; do not collect user measurements or results.
2. Classify whether the last App Store version is schema-compatible and still
   passes every safety invariant against data written by the candidate.
3. Prefer a forward hotfix when downgrading would encounter a newer schema. A
   rollback is allowed only after upgrade/downgrade fixtures prove it cannot
   destroy, reinterpret, or synthesize state.
4. Re-run the complete release-candidate gate on the exact replacement commit.
5. Submit/expedite the replacement and pause phased release. Public v1 has no
   remote kill switch; do not introduce one during an incident.
6. Publish support language that states the affected build and safe workaround
   without implying a result is proof or safe-to-drive clearance.

## Rehearsal

Before external TestFlight, rehearse with a synthetic device/container:

1. Install version N and create eligible and ineligible synthetic records.
2. Upgrade to N+1 and verify migration, History bounds, readiness, and deletion.
3. Attempt the proposed rollback path to N. If N cannot safely read N+1 data,
   abort rollback and rehearse a forward N+2 hotfix instead.
4. Corrupt one copied archive, verify quarantine and cleared readiness, then
   verify Delete all local data removes active and quarantined files.
5. Record result bundles, hashes/build numbers, operator, defects, and retest.

No rollback is complete until a clean install and an upgrade install both pass,
Home/get-home actions remain available, and the archive boundary gate proves the
public binary has not widened.
