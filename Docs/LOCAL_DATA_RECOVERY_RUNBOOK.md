# Local Data Recovery Runbook

Scope: public v1 local History, baseline/research summaries, deletion barriers,
and temporary research exports. Public v1 has no account or server copy to
restore from.

## Safety rules

1. Never edit a person's archive in place or fabricate replacement sessions.
2. Never clear a deletion barrier just to make readiness reappear.
3. Never ask a user to email an archive, screenshot a result, or send camera data.
4. A failed decode means “not available,” never “normal,” “clear,” or baseline-ready.
5. Preserve the original bytes in quarantine until the person chooses full deletion.

## What the app does automatically

| Store | Active location inside the app container | Failure behavior |
| --- | --- | --- |
| Baseline/session summaries | `Application Support/Sober/Research/research-sessions-v2.json` | schema 1 migrates to schema 2; malformed, duplicate, unsupported-record, or future-schema data moves to `Research/Quarantine/`; measured readiness clears |
| Local History | `Application Support/Sober/History/check-history-v1.json` | malformed, duplicate, unsupported-record, or future-schema data moves to `History/Quarantine/`; History becomes unavailable/empty without changing the baseline scorer |
| Prepared research export | temporary `sober-research-export-*.json` | removed by reset/deletion and never used as an input archive |

Files are written atomically and receive best-effort complete-until-first-unlock
protection. Quarantine is a preservation boundary, not an alternate source of
truth: the app never decodes quarantined data back into readiness.

## User-visible triage

1. Confirm which surface reports the problem: History or Your Steady/baseline.
2. Confirm Home, ride, call, and message actions remain available.
3. Relaunch once. A relaunch may complete a supported migration, but must not
   change a corrupt archive into a measured baseline.
4. If the person does not need the old local record, use Settings → Delete all
   local data. Explain that this removes active and quarantined copies and starts
   the baseline from zero.
5. If deletion reports failure, do not claim success. Keep the deletion barrier
   active, collect only app version/device/OS and the exact displayed error, and
   escalate to engineering.

## Engineering triage on an authorized test device

1. Record build, commit, device, OS, and whether this was install, upgrade, or
   rollback. Do not collect the person's identity or result.
2. Reproduce with a synthetic fixture matching the schema/failure class.
3. Inspect only a copied app container supplied through the approved internal
   support process. Keep it access-controlled and do not upload it to issue
   trackers, chat, analytics, or model-training systems.
4. Hash the quarantined copy, preserve it read-only, and identify whether the
   failure is decode, validation, file protection, capacity, or atomic-write.
5. Fix with a versioned copy/migrate/validate/write path. The old bytes remain
   quarantined until the new document is proven readable.
6. Add a regression fixture and prove zero eligible records still means zero
   baseline readiness.

## Exit criteria

- Home and get-home actions were never blocked.
- No unmeasured or recovered value was presented as measured.
- Deletion removed active, legacy, quarantined, and prepared-export copies, or
  the UI truthfully reports that deletion is still pending/failed.
- Relaunch and reset cannot recreate synthetic sessions.
- The incident record contains no measurement, result, contact, address, or raw
  archive payload.
