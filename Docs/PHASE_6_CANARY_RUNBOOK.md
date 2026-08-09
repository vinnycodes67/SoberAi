# Phase 6: controlled rollout and canary

Phase 6 protects people while Sober learns from its first real distribution.
It does not add a telemetry SDK, a tracking endpoint, or remote result logging.
The public binary keeps the Phase 5 no-provider and no-configured-endpoint
boundary.

## Release-channel correction

Apple's native phased release applies to **version updates**. It does not stage
the first App Store version. For Sober's first public release, use controlled
TestFlight cohorts in this order:

1. `internal`
2. `external-small`
3. `external-expanded`
4. `candidate-complete`
5. manual first public release after every submission gate passes

For a later App Store update, Apple's automatic-update schedule is day 1: 1%,
day 2: 2%, day 3: 5%, day 4: 10%, day 5: 20%, day 6: 50%, and day 7: 100%.
Anyone can still download the update manually during that period. App Store
Connect can pause the phased update for a cumulative 30 days and resume from
the same day. See Apple's [phased-release documentation](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/).

## What can be observed without a telemetry provider

| Signal | Approved source | Limitation |
| --- | --- | --- |
| Sessions and crashes | App Store Connect aggregate | Includes only users who opted into sharing diagnostics; usage metrics require Apple's privacy threshold |
| TestFlight crashes | TestFlight / Xcode Organizer aggregate | TestFlight crash reporting is not evidence of public-population behavior |
| Check started/completed | Consented manual cohort tally | Not available for the general public without adding reviewed collection |
| Baseline accepted/excluded | Consented manual cohort tally | Counts only; never include measurements or exclusion details tied to a person |
| Technical inconclusive reasons | Consented manual cohort tally | Broad reason counts only: camera unavailable, permission, capture quality, interruption, task quality, other technical |
| Support issues | Aggregate support log | Severity counts only; the canary file contains no message text or identity |

Apple says App Store Connect usage data comes only from users who agreed to
share diagnostics and appears only after enough data is available. Treat it as
partial evidence, not a census. See [App usage](https://developer.apple.com/help/app-store-connect-analytics/engagement/app-usage/)
and [App metrics](https://developer.apple.com/help/app-store-connect/reference/app-metrics/).

If an approved source cannot produce a metric before the next expansion, the
verdict is **HOLD**. Do not widen the cohort to manufacture sample size.

## Freeze the policy before observing data

Copy the synthetic example outside the committed source tree:

```bash
mkdir -p .artifacts/release
cp Release/phase6-canary.example.json .artifacts/release/phase6-canary.json
```

Change `evidenceKind` to `production`, set the exact version/build/commit and
rollout channel, and replace the example thresholds with the written policy
approved by founder, engineering, privacy/legal, and QA. The values in the
example are executable synthetic fixtures, not evidence-backed product targets.
Do not tune thresholds after seeing the first window unless the policy change is
documented and all four owners reapprove it.

Use at least two non-overlapping windows at every expansion checkpoint. Run:

```bash
node Scripts/release-ops.mjs canary \
  .artifacts/release/phase6-canary.json \
  --output .artifacts/release/phase6-canary-report.json
```

The output path is write-once. A second run must use a new path so evidence is
not silently overwritten.

## Verdicts

| Verdict | Exit | Meaning | Required action |
| --- | ---: | --- | --- |
| `CONTINUE` | 0 | Production evidence, approvals, sample sizes, reviews, and thresholds pass | Expand only to the next approved stage |
| `HOLD` | 2 | Evidence is synthetic/incomplete, sample is too small, P1 is open, or a quality threshold missed in consecutive windows | Do not expand; investigate or collect the next approved aggregate window |
| `PAUSE` | 3 | P0, critical safety/privacy/data incident, or persistent stability failure | Freeze the cohort or pause App Store phased release and open the rollback runbook |
| `INVALID` | 1 | Schema, chronology, phase schedule, count arithmetic, or privacy contract is wrong | Fix the evidence file; it cannot support a release decision |

A single rate miss is recorded but does not alert. Two consecutive misses are
required by default, matching the canary rule against transient noise. Critical
incidents and P0 support issues pause immediately.

## Input privacy contract

The evaluator accepts only fixed aggregate fields. It rejects extra keys, so a
person-level record cannot quietly enter the canary file.

Allowed:

- release identity and rollout stage;
- aggregate denominators and counts;
- aggregate technical-reason counts;
- P0/P1/P2 totals;
- counts of the five critical incident classes;
- approval and 7-day/30-day review booleans.

Forbidden:

- screening measurements, scores, thresholds, or individual result states;
- participant, device, session, contact, phone, email, or account identifiers;
- camera/face/gaze samples;
- coordinates, addresses, routes, or Safety Circle content;
- free-form support messages.

Do not work around rejection by putting sensitive content in a window ID. IDs
are restricted to short lowercase slugs.

## Daily operating loop

1. Confirm the candidate commit and build match the processed TestFlight/App
   Store Connect build.
2. Export Apple aggregate stability evidence and record its opt-in/sample limits.
3. Add only approved aggregate tallies from the consented cohort and support log.
4. Run the evaluator before adding testers or allowing the next automatic-update day.
5. On `PAUSE`, name an incident lead and follow `RELEASE_ROLLBACK_RUNBOOK.md`.
6. On `HOLD`, keep the current cohort fixed. Do not treat missing evidence as healthy.
7. On `CONTINUE`, retain the JSON report and record the expansion owner/time.

## Seven-day review

The founder, engineering, privacy/legal, and QA owners review:

- every pause/hold and threshold change;
- crash and launch diagnostics from Apple;
- completion, exclusion, and inconclusive reason aggregates;
- support misunderstandings about “safe,” “pass,” parents, or proof;
- any data deletion, migration, camera, permission, or get-home failure.

Set `reviews.day7.due`, `completed`, and `approved` truthfully in a final
production canary report. A due but incomplete review produces `HOLD`.

## Thirty-day review and Phase 6 exit

Repeat the same review with the longer window. Phase 6 exits only when:

- the controlled rollout has completed;
- no critical incident, P0, or high-risk P1 remains;
- the 7-day and 30-day reviews are completed and approved;
- the final production canary report returns `CONTINUE`;
- all retained evidence belongs to the same version, build, commit, and archive.

Guardian, Circle, APNs, accounts, model training, and new data collection remain
separate v1.1 work. A successful v1 canary does not qualify them.
