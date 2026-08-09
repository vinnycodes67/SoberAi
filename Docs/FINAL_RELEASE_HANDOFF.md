# Final release handoff

Phase 6 is the last numbered phase in `APP_STORE_MASTER_PLAN.md`. This handoff
is the final closure gate, not a Phase 7 feature build. It prevents “the code is
done” from being confused with “the product is released and reviewed.”

## Closure command

After the 30-day review, copy the template into ignored evidence storage:

```bash
mkdir -p .artifacts/release
cp Release/final-release-evidence.example.json \
  .artifacts/release/final-release-evidence.json
```

Change `evidenceKind` to `production`, enter the exact signed candidate
identity, replace every placeholder URL, mark only gates with retained evidence,
and record all five signoffs. Then run from a clean checkout of the candidate:

```bash
node Scripts/release-ops.mjs final \
  .artifacts/release/final-release-evidence.json \
  --output .artifacts/release/final-release-report.json
```

`READY` exits 0. `BLOCKED` exits 2. Invalid or placeholder production evidence
exits 1. The output is write-once.

## What `READY` proves

- the evidence describes the exact Git commit being checked;
- the worktree is clean;
- the archived app's version, build, bundle ID, and binary SHA-256 match the
  candidate evidence;
- Phase 4 device evidence and Phase 5 signoffs are complete;
- the signed archive was validated and processed by App Store Connect;
- privacy/support URLs, metadata, screenshots, privacy answers, and legal review
  are approved;
- no P0 or high-risk P1 is open;
- the controlled rollout, 7-day review, and 30-day review are complete;
- the referenced production canary report says `CONTINUE` and matches the same
  version, build, and commit;
- founder, engineering, design, privacy/legal, and QA signed the same candidate;
- a rollback owner is named.

The command validates evidence consistency. It cannot sign for a person, create
an Apple account, validate a legal claim, or fabricate a physical-device result.

## Current closure blockers

As of August 9, 2026, this branch cannot produce `READY` because:

- no paired physical iPhone or completed Phase 4 device matrix is available;
- no Apple signing team or App Store Connect build has been supplied;
- no live support or privacy-policy URL has been supplied and linked in-app;
- category, age rating, export compliance, and medical-claim review need founder
  and counsel decisions;
- screenshots and five-owner Phase 5 signoff are incomplete;
- no real controlled rollout, production canary, 7-day review, or 30-day review exists.

These are release gates, not coding TODOs. Leave their booleans false until the
evidence exists.

## Final operating sequence

1. Finish every row in `PHASE_4_DEVICE_GATES.md` on the signed build.
2. Complete and sign `PHASE_5_RELEASE_CHECKLIST.md`.
3. Validate, upload, process, and install the exact App Store Connect build.
4. Run the first-release TestFlight cohorts or a native phased rollout for a
   later update using `PHASE_6_CANARY_RUNBOOK.md`.
5. Complete the 7-day and 30-day reviews.
6. Run the closure command from the exact clean candidate commit.
7. Retain the final JSON report, checklists, archive hash, App Store Connect
   links, screenshots, crash evidence, and signoff record together.
8. Tag the released commit only after `READY` and founder approval. This script
   deliberately does not create or push a tag.

## After closure

Freeze public v1 safety semantics during the stability window. Route new
Guardian, Circle, APNs, identity, or research work through the separate v1.1
qualification program in the master plan. Any new permission, endpoint, SDK,
data transmission, result semantics, or claim reopens privacy, metadata,
device, review, and canary gates.
