# App Review reply — Guideline 2.1, TrueDepth API

Paste the text below the line into App Store Connect → the rejected submission
→ Reply to App Review. Send it only after the updated privacy policy is live at
the URL below (publish `SupportSite/privacy.html` and `styles.css` to the
`vinnycodes67/SoberSupport` repository and check the page loads).

---

Hello,

Thank you for the review. Below are complete answers about Sober's use of the TrueDepth API. We have also updated our privacy policy with a dedicated face-data section, and build 2026110101 shows the same text in the app (Settings → Privacy policy) and clears per-frame face data from memory as soon as the eye task ends.

**1. What information is the app collecting using the TrueDepth API?**

Sober uses ARKit face tracking (ARFaceTrackingConfiguration / ARFaceAnchor) only during a check or baseline session, while the camera preview is on screen. During the 11- to 25-second eye task it reads, on each frame:
- the left and right eye transforms (eye position and gaze direction);
- the eyeBlinkLeft and eyeBlinkRight blend-shape values;
- the face anchor transform (head position and steadiness relative to the camera) and whether more than one face is tracked;
- average brightness of the camera image and ARKit's light estimate, used only to check lighting.

Sober does not use the face mesh geometry, does not create a face print or any biometric identifier, and never saves camera images, video, depth data, or audio.

**2. For what purposes is this information collected? Planned use, sharing, retention, deletion, and storage.**

- Use: (a) quality gating: confirming the face is centred, at a good distance, steady, and well lit, and showing guidance when it is not; (b) calculating eye-movement measures (fixation steadiness, smooth-pursuit error, saccade accuracy, left/right asymmetry, blink rate) that produce the on-screen result for that check and, for baseline sessions, the user's personal baseline. It is not used for advertising, tracking, identification, authentication, or machine-learning training, and it is never sold.
- Storage: per-frame face data is kept only in memory, in a buffer capped at 1,800 samples, and is discarded when the eye task ends or is left. It is never written to disk. The app saves only derived numbers, on the device, in the app's private container with iOS Data Protection: the eye-movement and capture-quality measures from baseline sessions, and, for each check, its date, result state, and a capture-quality score in History.
- Retention: baseline summaries are kept until the user taps Settings → Delete all local data or deletes the app. History keeps at most 100 entries, and entries are removed automatically after 90 days.
- Deletion: Settings → Delete all local data permanently removes all baseline summaries and History; deleting the app removes everything. Users can also turn off camera access at any time, after which the app uses a no-camera path and collects no face data.
- Sharing: none (see 3).

**3. Will the data be shared with any third parties? Where will this information be stored?**

No. Face data and anything derived from it never leave the device. The public app has no server, account, analytics, advertising, or third-party SDK, and it makes no network requests with this data. It is not shared with us (the developers) or with any third party. All storage is local to the user's iPhone as described above. The only way a copy can leave the device is a whole-device iCloud or computer backup that the user controls; we have no access to those backups.

**4. Where in the privacy policy is face data explained?**

Privacy Policy URL: https://vinnycodes67.github.io/SoberSupport/privacy.html

The section "Face data (TrueDepth camera)" (https://vinnycodes67.github.io/SoberSupport/privacy.html#face-data) covers everything, with these subsections:
- Collection: "What face data Sober collects"
- Use: "How face data is used"
- Storage and retention: "Where face data is stored and how long it is kept"
- Disclosure and sharing: "Sharing and third parties"
- Deletion: "Deleting face data"

The same information is in the app under Settings → Privacy policy, and in the onboarding consent, which requires explicit agreement to on-device face and eye landmark processing before any check can run.

**5. Quoted privacy policy text concerning face data:**

> **Face data (TrueDepth camera)**
>
> Sober uses Apple’s ARKit face tracking with the iPhone TrueDepth camera only while you run a check or a baseline session and the camera preview is on screen. This section describes everything Sober does with that face data.
>
> **What face data Sober collects**
>
> During the 11- to 25-second eye task, Sober reads the following from ARKit on each camera frame:
>
> - the position and direction of each eye (left and right gaze);
> - how closed each eye is (ARKit’s eye-blink values);
> - the position and steadiness of your head relative to the camera, and whether more than one face is in view;
> - simple image brightness statistics and ARKit’s light estimate, used only to check lighting.
>
> Sober does not use the face mesh to identify you, does not create a face print or other biometric identifier, and does not save camera images, video, depth maps, or audio.
>
> **How face data is used**
>
> Face data is used only to (1) check that the capture is usable — your face is centred, at a good distance, steady, and well lit — and to guide you if it is not, and (2) calculate eye-movement measures such as fixation steadiness, how closely your eyes follow a moving dot, saccade accuracy, left–right differences, and blink rate. These measures produce the on-screen result for that check and, for baseline sessions, your personal baseline. Face data is not used for advertising, marketing, tracking, identification, authentication, or training machine-learning models, and it is never sold.
>
> **Where face data is stored and how long it is kept**
>
> The per-frame face data above stays in the iPhone’s memory, in a buffer capped at about 1,800 samples, and is discarded when the eye task ends or you leave it. It is never written to storage.
>
> Sober saves only derived numeric summaries, never images or per-frame landmarks, and only on your iPhone in the app’s private container with iOS file protection:
>
> - Baseline sessions: the eye-movement measures and capture-quality numbers from each baseline session, so later checks can be compared against your own baseline. They are kept until you choose Delete all local data or delete the app.
> - Check History: the date, the result state, and a capture-quality score for each check. History is limited to the newest 100 entries, and entries are removed after 90 days.
>
> **Sharing and third parties**
>
> Face data and the summaries derived from it are not transmitted off your iPhone. Sober has no server for the public app and does not share face data with Sober’s developers or any third party, including analytics, advertising, or data-broker services. The only copy that can leave the device is an iCloud or computer backup of the whole iPhone that you control through Apple settings; Sober does not receive or have access to those backups.
>
> **Deleting face data**
>
> Use Settings → Delete all local data in Sober to permanently remove all baseline summaries and History from this iPhone, or delete the app. Per-frame face data is already deleted automatically at the end of every task. You can also turn off camera access in iPhone Settings at any time; Sober then uses its no-camera path and collects no face data.

Please let us know if you need anything else.

Thank you.
