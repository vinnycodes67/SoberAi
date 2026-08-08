# Phase 0 execution record

Date: August 8, 2026

## Preserved starting point

The 38-file pre-existing worktree was audited before Phase 0 changes began. Its required project files and assets were checkpointed without discarding or rewriting the co-founder work:

- Branch: `codex/phase0-public-internal`
- Checkpoint: `eb67a60 Checkpoint audited App Store preparation work`
- Baseline at the checkpoint: 87 iOS tests and 22 backend tests passing

## Implemented

- Guardian no longer gates a private Sober check. Five eligible baseline sessions are the only readiness requirement.
- `Sober` is the public target. It has no Guardian, Circle Map, Research, or founder-preview routes and no location, background-location, local-network, or Guardian relay configuration.
- `SoberInternal` is a separately compiled target with `INTERNAL_BUILD`, a separate bundle identifier, and the Guardian, Circle Map, Research, and founder routes.
- The launch sequence is a canonical matte-black and orange reveal: 420 ms hold plus a 140 ms crossfade. Reduce Motion uses a 120 ms static handoff.
- Live checks now pass the eligible personal baseline into the screening engine.
- Unmeasured accessibility tasks remain absent data instead of becoming favorable numeric measurements.
- Persisted research metrics retain explicit reaction and timing measurement state while continuing to decode legacy schema-version-1 records.

## Verification

Environment: Xcode 26.6 on macOS 26.4.1.

| Gate | Result |
| --- | --- |
| Public Debug simulator build | Passed |
| Internal Debug simulator build | Passed |
| Public Release simulator build | Passed |
| Internal Release simulator build | Passed |
| iOS unit tests | 98 passed, 0 failed |
| Backend tests | 22 passed, 0 failed |
| Public Release permission and relay keys | All absent |
| Internal Release permission and relay keys | All present |
| Public Release `INTERNAL_BUILD` condition | Absent |
| Internal Release `INTERNAL_BUILD` condition | Present |
| Public Release founder and research route copy | Absent |
| Swift diff whitespace validation | Passed |

The iOS test result bundle is at `/tmp/SoberPhase0Tests/Logs/Test/Test-Sober-2026.08.08_05-36-19--0500.xcresult` on the verification machine. Physical-device camera, location, notification, and two-device Guardian checks remain part of the later hardware QA gate.
