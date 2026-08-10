import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import {
  evaluateCanary,
  evaluateFinalReadiness,
  validateCanary,
  validateFinalEvidence,
} from "../release-ops.mjs";

const canaryTemplate = JSON.parse(
  fs.readFileSync(new URL("../../Release/phase6-canary.example.json", import.meta.url), "utf8")
);
const finalTemplate = JSON.parse(
  fs.readFileSync(new URL("../../Release/final-release-evidence.example.json", import.meta.url), "utf8")
);

function clone(value) {
  return structuredClone(value);
}

function productionCanary() {
  const input = clone(canaryTemplate);
  input.evidenceKind = "production";
  return input;
}

function productionFinal() {
  const input = clone(finalTemplate);
  input.evidenceKind = "production";
  input.evidence.privacyPolicyURL = "https://sober.example/privacy";
  input.evidence.supportURL = "https://sober.example/support";
  input.evidence.appStoreConnectBuildURL = "https://appstoreconnect.apple.com/apps/123/builds/100";
  for (const key of Object.keys(input.gates)) input.gates[key] = true;
  for (const key of Object.keys(input.signoffs)) input.signoffs[key] = true;
  return input;
}

test("healthy approved production aggregates can continue", () => {
  const report = evaluateCanary(productionCanary());
  assert.equal(report.status, "CONTINUE");
  assert.deepEqual(report.reasons, []);
  assert.deepEqual(report.warnings, []);
});

test("synthetic aggregates can exercise policy but cannot authorize rollout", () => {
  const report = evaluateCanary(clone(canaryTemplate));
  assert.equal(report.status, "HOLD");
  assert.match(report.warnings.join("\n"), /synthetic evidence/);
});

test("one transient stability miss does not trigger the two-window pause", () => {
  const input = productionCanary();
  input.windows[1].crashFreeSessionsPercent = 99;
  const report = evaluateCanary(input);
  assert.equal(report.status, "CONTINUE");
});

test("two consecutive stability misses pause rollout", () => {
  const input = productionCanary();
  for (const window of input.windows) window.crashFreeSessionsPercent = 99;
  const report = evaluateCanary(input);
  assert.equal(report.status, "PAUSE");
  assert.match(report.reasons.join("\n"), /crash-free sessions/);
});

test("two consecutive quality misses hold expansion", () => {
  const input = productionCanary();
  for (const window of input.windows) {
    window.counts.checksCompleted = 10;
  }
  const report = evaluateCanary(input);
  assert.equal(report.status, "HOLD");
  assert.match(report.warnings.join("\n"), /check completion/);
});

test("a privacy incident pauses immediately", () => {
  const input = productionCanary();
  input.windows[1].criticalIncidents.privacy = 1;
  const report = evaluateCanary(input);
  assert.equal(report.status, "PAUSE");
  assert.match(report.reasons.join("\n"), /privacy incident/);
});

test("a due review that is not approved holds expansion", () => {
  const input = productionCanary();
  input.reviews.day7.due = true;
  const report = evaluateCanary(input);
  assert.equal(report.status, "HOLD");
  assert.match(report.warnings.join("\n"), /day7 review/);
});

test("insufficient aggregate samples hold expansion", () => {
  const input = productionCanary();
  for (const key of Object.keys(input.windows[1].counts)) input.windows[1].counts[key] = 0;
  for (const key of Object.keys(input.windows[1].technicalInconclusiveReasons)) {
    input.windows[1].technicalInconclusiveReasons[key] = 0;
  }
  const report = evaluateCanary(input);
  assert.equal(report.status, "HOLD");
  assert.match(report.warnings.join("\n"), /sample is 0/);
});

test("canary schema rejects individual measurements and identifiers", () => {
  const input = productionCanary();
  input.windows[0].measurements = [{ participantId: "person-1", reactionMs: 300 }];
  const issues = validateCanary(input);
  assert.ok(issues.some((issue) => issue.includes("measurements is not allowed")));
});

test("canary schema rejects a phase percentage that does not match Apple's schedule", () => {
  const input = productionCanary();
  input.release.rolloutChannel = "app-store-phased-update";
  input.release.rolloutStage = "day-1";
  input.release.phasedReleaseDay = 1;
  input.release.phasedReleasePercent = 100;
  const issues = validateCanary(input);
  assert.ok(issues.some((issue) => issue.includes("must be 1 on day 1")));
});

test("canary schema requires technical reason totals to reconcile", () => {
  const input = productionCanary();
  input.windows[0].technicalInconclusiveReasons.cameraUnavailable = 10;
  const issues = validateCanary(input);
  assert.ok(issues.some((issue) => issue.includes("must sum to counts.technicalInconclusive")));
});

test("final template remains blocked", () => {
  const input = clone(finalTemplate);
  assert.deepEqual(validateFinalEvidence(input), []);
  const report = evaluateFinalReadiness(input, {
    expectedCommit: input.candidate.commit,
    cleanWorktree: true,
    pathExists: () => true,
  });
  assert.equal(report.status, "BLOCKED");
  assert.match(report.blockers.join("\n"), /template evidence/);
});

test("complete matching production evidence can close the roadmap", () => {
  const input = productionFinal();
  const report = evaluateFinalReadiness(input, {
    expectedCommit: input.candidate.commit,
    cleanWorktree: true,
    pathExists: () => true,
    inspectArchive: () => ({
      version: input.candidate.version,
      build: input.candidate.build,
      bundleIdentifier: input.candidate.bundleIdentifier,
      binarySHA256: input.candidate.archiveSHA256,
    }),
    readJson: () => ({
      status: "CONTINUE",
      evidenceKind: "production",
      release: {
        version: input.candidate.version,
        build: input.candidate.build,
        commit: input.candidate.commit,
      },
      reviews: {
        day7: { approved: true },
        day30: { approved: true },
      },
    }),
  });
  assert.equal(report.status, "READY");
  assert.deepEqual(report.blockers, []);
});

test("final gate refuses commit drift and dirty worktrees", () => {
  const input = productionFinal();
  const report = evaluateFinalReadiness(input, {
    expectedCommit: "2222222222222222222222222222222222222222",
    cleanWorktree: false,
    pathExists: () => true,
  });
  assert.equal(report.status, "BLOCKED");
  assert.ok(report.blockers.some((blocker) => blocker.includes("does not match HEAD")));
  assert.ok(report.blockers.includes("Git worktree is not clean"));
});

test("final gate refuses missing evidence", () => {
  const input = productionFinal();
  const report = evaluateFinalReadiness(input, {
    expectedCommit: input.candidate.commit,
    cleanWorktree: true,
    pathExists: (relativePath) => !relativePath.includes("phase6"),
    readJson: () => ({ status: "HOLD", evidenceKind: "production" }),
  });
  assert.equal(report.status, "BLOCKED");
  assert.ok(report.blockers.some((blocker) => blocker.includes("does not exist")));
});

test("final gate refuses a non-continuation canary", () => {
  const input = productionFinal();
  const report = evaluateFinalReadiness(input, {
    expectedCommit: input.candidate.commit,
    cleanWorktree: true,
    pathExists: () => true,
    inspectArchive: () => ({
      version: input.candidate.version,
      build: input.candidate.build,
      bundleIdentifier: input.candidate.bundleIdentifier,
      binarySHA256: input.candidate.archiveSHA256,
    }),
    readJson: () => ({
      status: "HOLD",
      evidenceKind: "production",
      release: input.candidate,
      reviews: { day7: { approved: true }, day30: { approved: true } },
    }),
  });
  assert.equal(report.status, "BLOCKED");
  assert.ok(report.blockers.some((blocker) => blocker.includes("not an eligible CONTINUE")));
});

test("final gate refuses an archived binary hash mismatch", () => {
  const input = productionFinal();
  const report = evaluateFinalReadiness(input, {
    expectedCommit: input.candidate.commit,
    cleanWorktree: true,
    pathExists: () => true,
    inspectArchive: () => ({
      version: input.candidate.version,
      build: input.candidate.build,
      bundleIdentifier: input.candidate.bundleIdentifier,
      binarySHA256: "b".repeat(64),
    }),
  });
  assert.equal(report.status, "BLOCKED");
  assert.ok(report.blockers.some((blocker) => blocker.includes("archiveSHA256")));
});

test("production final evidence rejects placeholder URLs", () => {
  const input = productionFinal();
  input.evidence.supportURL = "https://example.invalid/support";
  const issues = validateFinalEvidence(input);
  assert.ok(issues.some((issue) => issue.includes("must be a live URL")));
});
