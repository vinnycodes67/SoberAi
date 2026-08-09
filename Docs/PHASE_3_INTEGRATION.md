# Phase 3 Integration Handoff

## Checkpoint

- Worktree: `/Users/vinaypulavarthy/SoberAi-phase2-integration`
- Branch: `codex/phase2-integration`
- Phase 2 base: `83b33cb`
- Scope: automation and release operations only; physical-device qualification
  remains Phase 4.

## Delivered

### Deterministic UI evidence

- Added a public-app XCUITest target.
- Added opt-in, Debug-only launch fixtures for onboarding, Home, History,
  Settings, Privacy Center, all three result states, interruption recovery, and
  camera-capture recovery.
- Fixture state is rebuilt before `AppModel` exists and only after the exact
  `-sober-ui-test-fixture` flag is recognized. Unknown/missing flags do nothing.
- Seeded History uses the production document schema and recent bounded records.
- Result fixtures use the existing non-live evaluation route and cannot persist
  a measured baseline.
- Production URL/deep-link registration remains absent. Stable test routing uses
  Debug-only launch arguments because an individual-result deep link would
  violate the anti-coercion release contract.
- Screenshot attachments are retained in `.xcresult` bundles. They are evidence
  snapshots, not claimed pixel-perfect golden diffs across OS rendering changes.

### Device and accessibility matrix

- Compact suite: iPhone SE (3rd generation) simulator, nine core route/safety
  scenarios.
- Large accessibility suite: iPhone 17 Pro Max simulator at Accessibility 3,
  with animations transaction-disabled for deterministic capture.
- `Scripts/prepare-ui-simulators.sh` selects the latest installed iOS runtime and
  creates/reuses named devices.
- `Scripts/run-ui-tests.sh` retains timestamped compact and accessibility result
  bundles under `.artifacts/ui-tests/`.

### Privacy and release gates

- Added `PrivacyInfo.xcprivacy` to both application targets.
- Declared app-local `UserDefaults` access and elapsed-time/system-boot access
  with the required reasons used by this codebase.
- Declared no tracking, tracking domains, or collected-data categories.
- The public/internal Release artifact gate now proves the manifest is bundled,
  validates required reasons, and retains the existing route, capability,
  entitlement, telemetry, and coercion boundaries.
- Added source metadata, font-license, and credential-signature checks.
- CI regenerates the project, proves the generated project is committed, runs
  public Debug unit/UI suites, internal Debug build, public/internal Release
  artifact inspection, backend preservation tests, plist checks, and clean-diff
  checks.

### Operations

- Crash-reporting privacy review keeps public v1 provider-free.
- Local corruption/quarantine/deletion recovery is documented.
- Client rollback stop-ship rules and an upgrade/rollback rehearsal are
  documented.

## Local commands

```bash
xcodegen generate
Scripts/check-release-metadata.sh
Scripts/run-ui-tests.sh
Scripts/check-public-binary.sh
npm test --prefix Backend
git diff --check
```

## Verification

- iOS Debug unit and invariant suite: 147 passed, 0 failed.
- Backend v1.1 preservation suite: 22 passed, 0 failed.
- Compact iPhone SE UI suite: 9 passed, 0 failed.
- iPhone 17 Pro Max Accessibility 3 UI suite: 1 passed, 0 failed.
- Public Release build, archive boundary inspection, and no-provider telemetry
  audit: passed.
- Internal Release build and forbidden-string sensitivity control: passed.
- Source and bundled privacy manifests, required-reason declarations, font
  assets/license, repository credential signatures, plists, shell syntax, and
  `git diff --check`: passed.

The local large-device simulator required one infrastructure retry after the
first XCUITest runner was killed before establishing its test connection. The
same already-built test passed with parallel workers disabled; no product
assertion failed. CI retains both device result bundles for every run.

## Evidence boundary

Simulator tests do not qualify ARKit/TrueDepth capture, real Face ID/Touch ID,
system passcode fallback, camera permission changes, incoming calls, lock-screen
interruptions, app-switcher shielding, actual Reduce Motion/VoiceOver focus, or
ride-app handoff behavior. Those remain explicit Phase 4 device gates.
