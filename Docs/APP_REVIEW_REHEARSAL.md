# App Review rehearsal

Use this runbook to prove that a reviewer can understand public v1 on a clean
device without drinking, completing five baseline sessions, or using an
internal fixture. It does not replace the Phase 4 TrueDepth, accessibility, or
TestFlight gates.

## Before the rehearsal

Record the candidate commit, marketing version, build number, iPhone model,
iOS version, and tester in `PHASE_5_RELEASE_CHECKLIST.md`. Use the public
`Sober` scheme. Do not use `SoberInternal` or any `-sober-*` launch argument.

Run the repeatable local package check:

```bash
Scripts/rehearse-app-store-package.sh
```

The script regenerates the project, scans both public and internal Release
artifacts, creates an unsigned public device archive, and prints the binary
SHA-256. A passing local rehearsal does not mean Apple has signed, validated,
uploaded, or processed the build.

## Clean-device walkthrough

Screen-record the complete sequence without cuts:

1. Delete Sober from the device, reinstall the signed candidate, and launch it.
2. Complete onboarding and both consent choices. Confirm the copy never claims
   diagnosis, BAC estimation, sobriety, a pass, or driving clearance.
3. On Home, confirm **Record a baseline session** is the live-check action and
   **Get home** remains available.
4. Under **Before a live check**, open **How results work**.
5. Confirm the page says **No result is a green light**, shows **Changes
   detected**, **No clear read**, and **No changes detected**, and labels them
   as examples that record no data.
6. Tap **Done**. Confirm Home still requests the first baseline session.
7. Open History and confirm **Nothing recorded yet**.
8. Open Settings → **What Sober stores**. Confirm the local storage, device
   backup, camera, location, and notification descriptions match the public
   binary and the person's Apple backup settings.
9. Use **Delete all local data**, relaunch, and confirm onboarding returns with
   no synthetic baseline, History, or Safety Plan.
10. Repeat the journey in airplane mode. Public v1 should not show network
    errors or a waiting spinner.

Retain the recording, clean-install screenshot, deletion/relaunch screenshot,
and an outbound proxy log if available. Link each artifact from the checklist.

## Signed archive and upload

After the founder provides an Apple Developer team and App Store Connect access:

1. Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the candidate.
2. In Xcode, select **Any iOS Device (arm64)** and archive the public `Sober`
   scheme in Release.
3. In Organizer, inspect the archive's bundle identifier, version, signing team,
   entitlements, privacy manifest, and symbols. Confirm no location, background,
   push, or Guardian capability is present.
4. Run **Validate App** and retain the validation result.
5. Use **Distribute App → App Store Connect → Upload**. Retain the upload result.
6. Wait for App Store Connect processing. Select the processed build and verify
   the displayed version/build, export-compliance prompt, privacy details, and
   TestFlight status.
7. Install that processed build through TestFlight and repeat the clean-device
   walkthrough. Locally installing the archive is not equivalent evidence.

Apple also supports Transporter and command-line upload, but Xcode Organizer is
the preferred founder rehearsal because it exposes signing and validation
issues before upload. See Apple's [upload documentation](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).

## Stop conditions

Stop the submission if any of these occurs:

- a public route exposes Guardian, Circle location sharing, Research Center, or
  founder sample-result controls;
- the reviewer examples write History or advance the baseline;
- any screen implies that a result clears someone to drive;
- the archive requests location, background, push, or an undeclared capability;
- the privacy answers differ from the archived binary;
- the policy/support URLs are missing, inaccessible, or inconsistent with the
  in-app privacy copy;
- the signed build differs from the commit and archive recorded in the checklist.

## App Review notes

Paste the reviewed notes from `APP_STORE_SUBMISSION.md`, not an improvised claim.
The critical instruction is: onboarding → Home → **Before a live check** →
**How results work**. Tell the reviewer that those are read-only examples, not
simulated measurements, and that a genuine comparison requires five accepted
sober baseline sessions.
