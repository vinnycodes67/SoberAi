# Phase 5 — App Store release checklist

One copy of this checklist belongs to one candidate build. Blank evidence or
signature fields mean not passed. Local automation proves package shape; only
Apple can prove validation, upload, processing, and TestFlight delivery.

## Candidate identity

| Field | Value |
| --- | --- |
| Commit | Release-readiness work started from `486a790c64a6722ee4b711a0bdfbb12067f82572`; replace with the exact signed candidate commit before distribution |
| Marketing version | `1.0` |
| Build number | `3` |
| Bundle identifier | `com.soberprototype.app` |
| Archive SHA-256 | Pending for the signed `1.0 (3)` candidate; the earlier `0.2.0 (2)` rehearsal is retired |
| Apple team | `CPRVLR97XJ` |
| App Store Connect app record | `6801400126` |
| TestFlight processed-build link | |
| Rehearsal device / iOS | Simulator: iPhone SE (3rd generation) and iPhone 17 Pro Max, iOS 26.5; physical device still open |
| Rehearsal date / tester | August 13, 2026 / Codex local automation |

## Engineering artifact

- [x] `xcodegen generate` leaves `Sober.xcodeproj` unchanged
- [x] Debug and Release build for `Sober` and `SoberInternal`
- [x] Unit tests pass
- [x] Targeted App Review-path UI tests pass
- [x] Backend preservation tests pass
- [x] `Scripts/check-release-metadata.sh` passes
- [x] `Scripts/check-public-binary.sh` passes
- [x] `Scripts/rehearse-app-store-package.sh` passes; archive path and hash recorded
- [ ] Signed public archive contains camera and Face ID descriptions
- [ ] Signed public archive contains no location, background, push, Guardian URL,
      third-party telemetry framework, or internal navigation
- [ ] Version and build are unique in App Store Connect

## Reviewer journey

- [ ] Clean public install starts at onboarding
- [ ] Home offers the first genuine baseline session and immediate get-home action
- [x] Home → **How results work** exposes all three states as read-only examples
- [x] Closing examples leaves baseline at zero and History empty
- [x] Privacy Center matches the archived permissions and data flow
- [ ] Delete all local data followed by relaunch recreates no synthetic state
- [ ] Airplane-mode journey completes without a network error
- [ ] Clean-device recording and screenshots retained

## Metadata and creative

- [x] Name, subtitle, description, and keywords approved
- [ ] Primary and secondary categories approved
- [ ] Current age-rating questionnaire completed; regional results recorded
- [ ] Export-compliance answer approved
- [ ] Copyright, contact, and review-contact details complete
- [x] Support URL resolves without authentication
- [x] Privacy policy URL resolves without authentication and is linked inside app
- [ ] Screenshots use real public states at accepted device dimensions
- [ ] Screenshots never imply a pass or driving clearance
- [ ] App Review notes use the exact public navigation path

## Privacy, safety, and legal

- [ ] App Privacy answers reconciled against the signed archived binary
- [x] `Data Not Collected` remains true: no off-device transmission or SDK added
- [ ] Camera frames are confirmed memory-only and absent from retained artifacts
- [ ] Retention and deletion language matches implementation
- [ ] Medical/impairment claims reviewed by qualified counsel
- [ ] Category and regulated-medical-device answer reviewed by counsel
- [ ] Age-positioning and alcohol-reference answers reviewed
- [ ] Support and privacy contacts own a response/deletion process

## Device, TestFlight, and App Store Connect

- [ ] Every required row in `PHASE_4_DEVICE_GATES.md` has retained evidence
- [ ] Xcode **Validate App** passes for this exact archive
- [ ] This exact archive uploads successfully
- [ ] App Store Connect processing completes without warning or rejection
- [ ] Processed build identity matches the candidate table
- [ ] Internal TestFlight install passes the clean-device review rehearsal
- [ ] Crash-free and abandonment gates meet the Phase 4 thresholds
- [ ] External TestFlight, if used, has privacy and legal approval
- [ ] Phased release and rollback owner confirmed

## Stop-ship blockers as of August 13, 2026

- Apple team `CPRVLR97XJ`, automatic signing, version `1.0`, and build `3` are
  configured. The first signed archive attempt reached Apple but failed because
  the team has no registered iPhone and therefore no development provisioning
  profile for `com.soberprototype.app`. Connect and register a device, then
  archive again; distribution signing and Apple validation remain open.
- No current signed physical-device or TestFlight evidence is recorded. Both a
  TrueDepth iPhone and a supported non-TrueDepth iPhone are needed because the
  App Store binary is installable on both and intentionally behaves differently.
- Matching support and privacy pages are live from the public
  `vinnycodes67/SoberSupport` Pages site with HTTPS enforced. The live HTML and
  CSS matched the reviewed local files byte-for-byte on August 15, 2026, and
  the public app links to the hosted policy from its in-app policy screen.
- Category, age questionnaire, export compliance, and medical-claim language
  still require founder/counsel decisions.
- Phase 4 TrueDepth, accessibility, offline-proxy, external-action, lifecycle,
  and crash-free gates remain open until their evidence is attached.
- Screenshot capture and final copy freeze remain open.

## Retained local evidence

- August 15 App Store-unblocker run: all 158 unit tests passed, the 22 backend
  tests passed, all 18 release-policy tests passed, and the public Release
  boundary passed with version `1.0 (3)` embedded. The targeted privacy-link UI
  test compiled but CoreSimulator failed before app launch with `Invalid device
  state`; this is not retained as passing UI evidence.
- `https://vinnycodes67.github.io/SoberSupport/` and
  `https://vinnycodes67.github.io/SoberSupport/privacy.html` returned HTTPS 200
  and matched the reviewed local HTML/CSS byte-for-byte. The deployed static-site
  source is public commit `0c9ed8b2e1a33a3030079a718cd22c36dc368efb` in
  `vinnycodes67/SoberSupport`; no application source or review phone is present.
- The first automatic-signing archive attempt reached Apple and failed closed:
  the team has no registered device and no matching development provisioning
  profile for `com.soberprototype.app`. No candidate archive was produced.

- Unit tests: 158 passed, 0 failed, 0 skipped in
  `.artifacts/unit-tests-final-20260813.xcresult`.
- Compact-device UI: all 22 current cases are covered — 21 passed in
  `.artifacts/ui-tests/small-20260814T025326Z-25662.xcresult`, and the added
  no-TrueDepth/small-screen fallback passed in
  `.artifacts/ui-tests/unsupported-camera-compact-rerun-20260813.xcresult`.
- Large-device accessibility UI: all seven current cases have passing retained
  evidence. Five passed in
  `.artifacts/ui-tests/large-accessibility-20260814T025326Z-25662.xcresult`;
  the previously skipped calibration case passed in
  `.artifacts/ui-tests/unsupported-camera-targeted-20260813.xcresult`; and the
  AX5 History/Settings test was split into two bounded one-launch cases, both
  passing in `.artifacts/ui-tests/ax5-split-tabs-20260813.xcresult`.
- Xcode 26's simulator test manager was materially slower when every UI test ran
  in one process: a consolidated rerun hit the old two-launch test's 120-second
  allowance. The test was split instead of increasing a global timeout; each
  replacement case now passes independently in 60 seconds or less.
- Backend: 22 passed; release-policy tooling: 18 passed; production dependency
  audit: 0 vulnerabilities.
- Xcode Release static analysis passed. Periphery found 120 dead-code findings,
  concentrated in deferred Guardian, research, and excluded pupil-model paths.
  That is a source-minimization follow-up, not evidence that those routes are
  reachable: the Release boundary scan separately proves the routes,
  permissions, endpoint, model, and push entitlements are absent from public v1.
- The repository has no checked-in SwiftLint policy. Running SwiftLint with its
  global defaults reports 206 pre-existing style/size findings (166 warnings,
  40 errors), chiefly large legacy types and line-length/naming rules. Compiler
  diagnostics and Xcode static analysis are clean; adopting a lint baseline and
  shrinking `AppModel` should be scheduled deliberately rather than mass-edited
  into this release candidate.
- Unsigned archive: `.artifacts/app-store-rehearsal/final-20260813/Sober.xcarchive`.
  This is package-shape evidence only; it cannot satisfy the signed archive,
  Apple validation, upload, processing, TestFlight, or physical-device rows.

## Signoff

| Owner | Name | Decision | Date | Evidence / notes |
| --- | --- | --- | --- | --- |
| Founder | | | | |
| Engineering | | | | |
| Design | | | | |
| Privacy / legal | | | | |
| QA | | | | |

All five owners sign the same candidate identity. Any code, metadata, privacy
answer, screenshot, or build-number change after signoff creates a new candidate
and requires the affected gates to be rerun.

## Apple references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Age ratings](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
