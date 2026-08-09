# Phase 6 — phased release and canary

The operational runbook for the first public build. Written to be usable at
2am by whoever is holding the pager, which for now is one person.

## Read this first: two things Phase 6 assumes that are not true

**1. There is no rollback.**

The App Store has no revert. Once a build is live, the only levers are:

- **Pause phased release** — stops new users receiving it. Everyone who already
  updated keeps the build.
- **Remove from sale** — stops new downloads. Existing installs are unaffected.
- **Expedited review** — a fix, typically hours to a day, not minutes.

So "rollback rehearsal" for this app means rehearsing *pause and hotfix*.
Anyone reading the plan's "rollback" language and expecting to restore a
previous version will lose time discovering otherwise during an incident.

The one genuine mitigation is that a v1 check is entirely local: there is no
backend to fail, no flag to flip, and nothing a server outage can break. The
failure modes are all in the binary, which is exactly why they cannot be undone
remotely.

**2. Most of the metrics Phase 6 lists cannot be measured.**

The plan asks to monitor local check completion, baseline exclusions, and
inconclusive technical reasons. The app collects none of that. The App Privacy
answer is "Data Not Collected", `PrivacyInfo.xcprivacy` declares an empty
collected-data array, and the Privacy Centre tells people nothing leaves the
device.

Instrumenting those metrics would mean transmitting data, which changes all
three at once. That is a product decision, not a monitoring detail.

| Metric | Available in v1? | How |
| --- | --- | --- |
| Crash-free sessions | Yes | App Store Connect / Xcode Organizer, no SDK, opt-in by the user to Apple |
| Hangs, launch time, memory | Yes | Xcode Organizer metrics |
| Install and update counts | Yes | App Store Connect |
| Ratings and reviews | Yes | App Store Connect |
| Support email themes | Yes | the inbox |
| Check completion rate | **No** | would require collection |
| Baseline exclusion rate | **No** | would require collection |
| Inconclusive reasons | **No** | would require collection |

**Recommendation:** ship v1 blind on product metrics and rely on crash data,
reviews, and support mail. Do not bolt on analytics to satisfy this phase. If
the product metrics are genuinely needed, they belong in v1.1 as an explicit,
opt-in, aggregate-only decision with the privacy answers, manifest, and Privacy
Centre updated together — and the boundary scan already fails the build if the
manifest changes without that being deliberate.

## Before releasing

Everything here must be true. The first four are machine-checked.

- [ ] `Scripts/check-public-binary.sh` passes on the exact archived build
- [ ] Unit and UI suites green on that commit
- [ ] Launch scorecard in the master plan fully ticked
- [ ] `Docs/PHASE_4_DEVICE_GATES.md` complete, every row with an artefact
- [ ] Submission decisions in `Docs/APP_STORE_SUBMISSION.md` resolved
- [ ] Support inbox monitored by a named person
- [ ] This runbook read by whoever is on call

## Phased release

Use Apple's phased release. It runs over seven days at roughly 1%, 2%, 5%, 10%,
20%, 50%, 100%, and it can be paused at any point.

Keep it on. The whole reason to accept a slow rollout is that this app can tell
someone something wrong about their own impairment, and a 1% first day bounds
how many people that can reach.

Do not manually accelerate. There is no deadline that justifies it.

| Day | Reach | What to look at |
| --- | --- | --- |
| 1 | ~1% | Crashes on launch or first check. Any crash at all is worth a look at this size. |
| 2 | ~2% | Crash-free rate stabilising; first reviews |
| 3 | ~5% | Hang rate; launch time on older devices |
| 4 | ~10% | Support mail themes |
| 5 | ~20% | Review sentiment: is anyone reading a result as clearance? |
| 6 | ~50% | Same, at volume |
| 7 | 100% | Full rollout |

## Halt criteria

Pre-committed, so the decision is not made under pressure by someone who wants
it to be fine. **Any one of these pauses the rollout immediately.** Pausing is
cheap and reversible; the alternatives are not.

**Halt and hotfix:**

- Crash-free sessions below 99.5%
- Any crash during a check, at any rate
- Any report of a result being shown as "safe", "passed", or "cleared"
- Any report of a baseline appearing ready without measured sessions
- Any data loss: history, baseline, or Safety Plan disappearing
- Any evidence of data leaving the device
- Any report of someone being made to run a check and show the result

**Halt and assess, no automatic hotfix:**

- A spike in one-star reviews describing the app as broken or useless
- Reviews indicating people expect a breathalyser — a claims problem, not a code
  problem, and fixed in metadata rather than a build
- Support volume beyond what one person can answer within a day

The last two are worth naming because they are the likely ones. This product's
most probable failure is not a crash; it is being misunderstood.

## If you halt

1. Pause phased release in App Store Connect. Do this first, before diagnosis.
2. Write down what you saw and when, before investigating. Incident memory
   rewrites itself.
3. Classify: does it mislead someone about their own impairment? If yes it is a
   P0 regardless of how few people are affected.
4. Fix on a branch, with a regression test that fails before the fix. This
   codebase has a habit of turning incidents into tests — keep it.
5. Full CI, boundary scan, and the relevant device gates before resubmitting.
6. Request expedited review only for a genuine safety issue. Spending that
   credibility on a cosmetic bug means not having it when it matters.
7. Resume phased release from the beginning, not from where it stopped.

## Reviews to hold

**Day 7.** Before going to 100%, or immediately after if it completed:

- Crash-free rate against the 99.5% target
- Every review read, not skimmed. Looking for one thing above all: is anyone
  treating a result as permission to drive?
- Support themes
- Anything from `PHASE_4_DEVICE_GATES.md` that shipped unverified, and whether
  the field contradicted it

**Day 30.** Before any feature work:

- Retention, if it can be seen at all without instrumentation
- Whether the five-session baseline ramp is stopping people before their first
  comparison. This is the most likely product failure and the hardest to see
  without analytics — reviews and support mail are the only signal.
- Whether the claims held up under public reading
- Only then, whether v1.1 Guardian should start

## What v1 cannot do to itself

Worth stating so nobody goes looking for a lever that does not exist:

- No remote kill switch. A check runs entirely on device.
- No feature flags. There is no backend to serve them.
- No forced update.
- No remote config to soften a claim. Copy changes ship in a build; only the
  App Store description and screenshots can be changed without one.

The only remote levers are the App Store listing and pausing distribution.
Everything else requires shipping.
