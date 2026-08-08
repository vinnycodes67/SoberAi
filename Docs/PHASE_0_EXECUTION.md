# Phase 0 execution record

Date: August 8, 2026

## Preserved starting point

The 38-file pre-existing worktree was audited before Phase 0 changes began. Its required project files and assets were checkpointed without discarding or rewriting the co-founder work:

- Branch: `codex/phase0-public-internal`
- Checkpoint: `eb67a60 Checkpoint audited App Store preparation work`
- Baseline at the checkpoint: 87 iOS tests and 22 backend tests passing

## Implemented

- Guardian no longer gates a private Sober check. Five eligible baseline sessions are the only readiness requirement.
- `Sober` is the public target. **The public build exposes no Guardian routes, permissions, configuration, or network endpoint.** It likewise exposes no Circle Map, Research, or founder-preview routes, and declares no location, background-location, or local-network capability.

  This is a statement about reachable surface, not about compiled code. Both targets compile the same sources, so Guardian types and the `/v1/guardian-relationships/` path string are present in the public binary. They are inert: no route reaches them, `SoberGuardianAPIURL` is absent from the public `Info.plist`, and `GuardianAPIClient` resolves a `nil` base URL and guards every request. Complete source-level exclusion is tracked as post-v1 hardening.
- `SoberInternal` is a separately compiled target with `INTERNAL_BUILD`, a separate bundle identifier, and the Guardian, Circle Map, Research, and founder routes.
- The launch sequence is a canonical matte-black and orange reveal: 420 ms hold plus a 140 ms crossfade. Reduce Motion uses a 120 ms static handoff.
- Live checks now pass the eligible personal baseline into the screening engine.
- Unmeasured accessibility tasks remain absent data instead of becoming favorable numeric measurements.
- Persisted research metrics retain explicit reaction and timing measurement state while continuing to decode legacy schema-version-1 records.
- The last public copy leak is closed. `CameraCalibrationView` no longer points a public user on unsupported hardware at founder previews that do not exist in their build.
- `Scripts/check-public-binary.sh` turns the boundary from a manual inspection into a runnable gate: it builds the public Release target, scans the binary for internal route copy, asserts the forbidden and required `Info.plist` keys, and then builds `SoberInternal` to prove every needle is actually detectable.

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
| `Scripts/check-public-binary.sh` | Passed (9 forbidden strings, 5 forbidden keys, 1 required key) |
| Forbidden-string sensitivity control | Passed (all 9 needles detectable in `SoberInternal`) |
| Swift diff whitespace validation | Passed |

The iOS test result bundle is at `/tmp/SoberPhase0Tests/Logs/Test/Test-Sober-2026.08.08_05-36-19--0500.xcresult` on the verification machine. Physical-device camera, location, notification, and two-device Guardian checks remain part of the later hardware QA gate.
