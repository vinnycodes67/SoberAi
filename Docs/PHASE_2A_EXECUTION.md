# Phase 2A execution record

Date: August 8, 2026

## Isolation and scope

- Base checkpoint: `9e73c6f` (`Migrate the check journey onto DesignKit, and isolate the stimulus from it`)
- Branch: `codex/phase2a-foundations`
- Worktree: `/Users/vinaypulavarthy/SoberAi-phase2a`
- DesignKit and feature-screen SwiftUI files were not edited.
- Privacy Lock and Settings/Privacy UI remain deferred to the integration pass.

## Foundations delivered

- `BaselineStore` is the only AppModel path to baseline/history records, exports, deletion, and participant-identity rotation.
- `PermissionStore` uses system camera authorization as truth and is injectable from AppModel and face capture.
- `PrivacyStore` owns consent, research preferences, Safety Plan, local profile, and consent-receipt defaults.
- The legacy baseline count cache is removed on store initialization and is never used to establish readiness.
- A synchronous, persisted deletion barrier blocks reads, appends, and exports before asynchronous deletion starts. It survives relaunch and remains closed if file deletion fails.
- Reset and delete clear in-memory records and internal founder-preview readiness immediately.
- Prepared exports are removed by deterministic participant filename even after an app relaunch.

## Archive integrity

- Store schema 1 migrates to schema 2 without changing session records.
- Malformed, unsupported-version, duplicate-ID, and unsupported-record archives are moved byte-for-byte into a protected Quarantine directory before an error is surfaced.
- Quarantined data cannot leave stale baseline readiness in memory.
- Delete All removes active, legacy, quarantined, and prepared-export copies without requiring successful decoding.

## Telemetry decision

Public v1 remains a no-provider build. The audit and ongoing release assertions are documented in `Docs/TELEMETRY_AUDIT.md`.

## Verification

| Gate | Result |
| --- | --- |
| Public Debug and unit-test build | Passed |
| Internal Debug build | Passed |
| Public Release build | Passed |
| Internal Release sensitivity build | Passed |
| iOS unit tests | 115 passed, 0 failed |
| Backend preservation tests | 22 passed, 0 failed |
| Public archive route, permission, URL, entitlement, relay, and telemetry checks | Passed |
| DesignKit and feature-screen diff boundary | Passed |
| `git diff --check` | Passed |
