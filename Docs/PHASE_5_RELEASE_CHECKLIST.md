# Phase 5 — App Store release checklist

One copy of this checklist belongs to one candidate build. Blank evidence or
signature fields mean not passed. Local automation proves package shape; only
Apple can prove validation, upload, processing, and TestFlight delivery.

## Candidate identity

| Field | Value |
| --- | --- |
| Commit | |
| Marketing version | |
| Build number | |
| Bundle identifier | `com.soberprototype.app` |
| Archive SHA-256 | |
| Apple team | |
| App Store Connect app record | |
| TestFlight processed-build link | |
| Rehearsal device / iOS | |
| Rehearsal date / tester | |

## Engineering artifact

- [ ] `xcodegen generate` leaves `Sober.xcodeproj` unchanged
- [ ] Debug and Release build for `Sober` and `SoberInternal`
- [ ] Unit tests pass
- [ ] Targeted App Review-path UI tests pass
- [ ] Backend preservation tests pass
- [ ] `Scripts/check-release-metadata.sh` passes
- [ ] `Scripts/check-public-binary.sh` passes
- [ ] `Scripts/rehearse-app-store-package.sh` passes; archive path and hash recorded
- [ ] Signed public archive contains camera and Face ID descriptions
- [ ] Signed public archive contains no location, background, push, Guardian URL,
      third-party telemetry framework, or internal navigation
- [ ] Version and build are unique in App Store Connect

## Reviewer journey

- [ ] Clean public install starts at onboarding
- [ ] Home offers the first genuine baseline session and immediate get-home action
- [ ] Home → **How results work** exposes all three states as read-only examples
- [ ] Closing examples leaves baseline at zero and History empty
- [ ] Privacy Center matches the archived permissions and data flow
- [ ] Delete all local data followed by relaunch recreates no synthetic state
- [ ] Airplane-mode journey completes without a network error
- [ ] Clean-device recording and screenshots retained

## Metadata and creative

- [ ] Name, subtitle, description, and keywords approved
- [ ] Primary and secondary categories approved
- [ ] Current age-rating questionnaire completed; regional results recorded
- [ ] Export-compliance answer approved
- [ ] Copyright, contact, and review-contact details complete
- [ ] Support URL resolves without authentication
- [ ] Privacy policy URL resolves without authentication and is linked inside app
- [ ] Screenshots use real public states at accepted device dimensions
- [ ] Screenshots never imply a pass or driving clearance
- [ ] App Review notes use the exact public navigation path

## Privacy, safety, and legal

- [ ] App Privacy answers reconciled against the signed archived binary
- [ ] `Data Not Collected` remains true: no off-device transmission or SDK added
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

## Stop-ship blockers as of August 9, 2026

- No Apple Developer team, signing identity, or App Store Connect credential has
  been supplied in this workspace.
- No current signed physical-device or TestFlight evidence is recorded.
- No live support URL or privacy policy URL has been supplied; Apple requires
  the privacy policy in metadata and accessible within the app.
- Category, age questionnaire, export compliance, and medical-claim language
  still require founder/counsel decisions.
- Phase 4 TrueDepth, accessibility, offline-proxy, external-action, lifecycle,
  and crash-free gates remain open until their evidence is attached.
- Screenshot capture and final copy freeze remain open.

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
