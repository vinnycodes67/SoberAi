# Phase 4 Integration Checkpoint

## Branch and scope

- Worktree: `/Users/vinaypulavarthy/SoberAi-phase4-integration`
- Branch: `codex/phase4-integration`
- UI/accessibility base: `8ccfc1e`
- Persistence/privacy/release branch merged: `df0b56b`
- Scope completed here: combine both histories without changing the dirty main
  worktree, repair their shared launch/test seam, and restore automated release
  gates.
- Scope still open: every physical-device and TestFlight row in
  `Docs/PHASE_4_DEVICE_GATES.md`.

## Integration decisions

Both Debug-only UI fixture systems remain because they prove different things:

- `UITestConfiguration` keeps the co-founder journey, public-boundary, and AX5
  suites on throwaway defaults and archive directories. It now creates the
  Phase 2 `LocalBaselineStore` instead of using the removed `researchStore`
  initializer. Seeded sessions therefore pass through the same migration and
  readiness path as production records.
- `UITestLaunchConfiguration` keeps deterministic direct fixtures for all three
  result states, interruption recovery, capture recovery, Privacy Center, and
  retained screenshots. It remains compiled only in Debug.

`SoberApp` recognizes either fixture contract, skips only the launch reveal for
an active test fixture, and otherwise uses the production model and routing.
The Xcode project was regenerated from one de-duplicated `SoberUITests` target
in `project.yml`; no generated-project conflict was hand-maintained.

The co-founder AX5 layout fixes, device-gate checklist, and UI tests remain
present. The Phase 2 store protocols, versioned migrations,
quarantine behavior, deletion barriers, Privacy Lock foundations, result
privacy boundary, privacy manifest, release inspections, and recovery/rollback
runbooks are now present on the same branch.

The duplicate CI definitions were consolidated into `.github/workflows/ci.yml`.
That workflow builds both public/internal schemes in Debug and Release, proves
the generated Xcode project is committed, runs the invariant suite, executes
both UI fixture families across compact and large simulators, retains their
`.xcresult` bundles, and performs the public/internal Release boundary scan.
Guardian backend tests remain visible but non-blocking because Guardian is not
part of public v1.

## Parallel co-founder branch

`origin/main` currently points to `04d4a88`, a separate branch line containing
the pupil/iris segmentation pipeline and an alternate UI/application structure.
It diverges before the Phase 1 checkpoint used here; a direct comparison spans
more than 100 files and would remove the current Phase 1 screens, tests, and
release documentation. It was intentionally not folded into this safety
checkpoint without a dedicated product/data-model reconciliation and review.

## Automated evidence

- iOS unit and invariant suite: 150 passed, 0 failed.
- Backend v1.1 preservation suite: 22 passed, 0 failed.
- Cross-harness integration smoke on the isolated Phase 4 simulator: 2 passed,
  0 failed. This covered the measured-baseline Home path and the no-signals
  result safety limit.
- Public Release build and archive boundary inspection: passed.
- Internal Release build and forbidden-string sensitivity control: passed.
- Privacy manifest/source metadata, required-reason declarations, font
  license/assets, credential signatures, plists, shell syntax, and
  `git diff --check`: passed.

The complete UI suites were started while another Claude session was running
multiple Xcode jobs. One shared-simulator run produced 11 passes, one expected
camera skip, one assertion timeout, and one killed runner. A fresh isolated
simulator then timed out initializing Accessibility before reaching a test.
Two cross-harness tests passed after the simulator was warm. These are machine
contention/runner outcomes, not a green full-matrix result, so the full combined
UI run remains a required CI gate rather than being reported as passed here.

## Physical-device status

`xcrun devicectl list devices` returned `No devices found` on August 9, 2026.
The live-device QA bridge was not installed because its first prerequisite, a
paired and trusted iPhone, was absent. No DebugBridge code or package was added
to either app target.

Therefore TrueDepth capture, Face ID/Touch ID, camera permission transitions,
incoming calls, screen locking, app-switcher shielding, VoiceOver focus,
Airplane Mode, proxy evidence, ride/call/message handoff, update/reinstall, and
TestFlight gates remain unverified. Use `Docs/PHASE_4_DEVICE_GATES.md` on a
connected TrueDepth iPhone and retain the evidence required by each row.

## Resume commands

```bash
xcrun devicectl list devices
xcodegen generate
xcodebuild -project Sober.xcodeproj -scheme Sober \
  -destination 'platform=iOS,id=<DEVICE_UDID>' build
Scripts/run-ui-tests.sh
Scripts/check-public-binary.sh
npm test --prefix Backend
```

Do not call Phase 4 complete until the physical-device checklist has retained
artifacts, TestFlight has no open P0 or high-risk P1, and the crash-free target
in the master plan is met.
