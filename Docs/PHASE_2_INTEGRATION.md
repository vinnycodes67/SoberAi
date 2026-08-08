# Phase 2 Integration Handoff

## Checkpoint

- Worktree: `/Users/vinaypulavarthy/SoberAi-phase2-integration`
- Branch: `codex/phase2-integration`
- Phase 1 base: `a96ee9b`
- Phase 2A foundations integrated as: `6c82333`

The main worktree was not modified. Its uncommitted `AppModel.swift` and
`CheckHistoryStore.swift` work remains in place for its owner.

## Delivered

### Privacy Lock

- Uses `LocalAuthentication` with `.deviceOwnerAuthentication`.
- Supports Face ID, Touch ID, and the system device-passcode fallback.
- Is off by default and can only be enabled after successful system authentication.
- Persists through `PrivacyStore` and is removed by the existing full reset.
- Starts locked after relaunch when enabled.
- Uses a 30-second monotonic inactivity window.
- Immediately places an opaque shield over protected routes when the scene becomes inactive.
- Dismisses History and Settings sheets before the app-switcher snapshot.
- Has no custom PIN, pattern, biometric storage, or recovery credential.

Protected routes:

- History
- Your Steady
- Settings and Privacy Center

Never gated:

- Home
- Live screening and results
- Ride
- Call
- Message

### Settings and privacy

- Settings shows whether Privacy Lock is on.
- Privacy Center explains exactly what the lock protects and what stays available.
- Camera permission status now reflects the system state.
- Denied or restricted camera access has an explicit route to iPhone Settings.
- Both app targets include the required Face ID usage description.

### Result privacy

- The live result says it is private context, not evidence for a parent, partner,
  employer, school, insurer, or authority.
- The result surface has no share sheet, export, transferable object, authenticated
  receipt, or verification route.
- Ride, Call, and Message URL actions remain because they are safety interventions,
  not result-sharing mechanisms.
- The public Release gate checks both the source boundary and the required copy in
  the compiled binary.

## Verification

- iOS Debug unit suite: 123 passed, 0 failed.
- Backend preservation suite: 22 passed, 0 failed.
- Public Release build: passed.
- Internal Release build and sensitivity control: passed.
- Public archive capability, plist, entitlement, telemetry, route, and result
  non-sharing checks: passed.
- `plutil` for both Info plists and the Xcode project: passed.
- `git diff --check`: passed.

## Remaining physical-device gate

LocalAuthentication and lifecycle policy are unit tested, and both targets compile in
Release. A physical iPhone must still verify Face ID or Touch ID presentation, system
passcode fallback, cancellation, app-switcher shielding, and returning after more than
30 seconds. That belongs in Phase 3 automation and Phase 4 device evidence and should
not be represented as completed by simulator tests.

## Next phase

Phase 3 should add the XCUITest target, deterministic launch fixtures, accessibility
and device-size snapshots, lifecycle UI tests, and CI release gates described in the
master plan.
