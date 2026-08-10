#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const PHASE_PERCENTAGES = new Map([
  [1, 1],
  [2, 2],
  [3, 5],
  [4, 10],
  [5, 20],
  [6, 50],
  [7, 100],
]);

const AGGREGATE_SOURCES = new Set([
  "app-store-connect-aggregate",
  "testflight-aggregate",
  "consented-manual-tally",
  "support-aggregate",
]);

const CRITICAL_INCIDENT_KEYS = [
  "baselineTruth",
  "privacy",
  "dataLoss",
  "coerciveCopy",
  "unsafeResult",
];

const FINAL_GATE_KEYS = [
  "phase4DeviceEvidenceComplete",
  "phase5SignoffsComplete",
  "signedArchiveValidated",
  "appStoreConnectProcessed",
  "privacyPolicyLiveAndLinked",
  "supportUrlLive",
  "legalApproved",
  "metadataApproved",
  "screenshotsApproved",
  "privacyAnswersReconciled",
  "noOpenP0OrHighRiskP1",
  "controlledRolloutCompleted",
  "phase6CanaryContinue",
  "day7ReviewApproved",
  "day30ReviewApproved",
  "rollbackOwnerAssigned",
];

const SIGNOFF_KEYS = ["founder", "engineering", "design", "privacyLegal", "qa"];

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, allowed, location, issues) {
  if (!isPlainObject(value)) {
    issues.push(`${location} must be an object`);
    return false;
  }

  const allowedSet = new Set(allowed);
  for (const key of Object.keys(value)) {
    if (!allowedSet.has(key)) issues.push(`${location}.${key} is not allowed`);
  }
  for (const key of allowed) {
    if (!(key in value)) issues.push(`${location}.${key} is required`);
  }
  return true;
}

function finiteNumber(value, location, issues, minimum = 0, maximum = Number.MAX_VALUE) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    issues.push(`${location} must be a number from ${minimum} through ${maximum}`);
    return false;
  }
  return true;
}

function nonnegativeInteger(value, location, issues) {
  if (!Number.isInteger(value) || value < 0) {
    issues.push(`${location} must be a nonnegative integer`);
    return false;
  }
  return true;
}

function booleanFields(value, keys, location, issues) {
  if (!exactKeys(value, keys, location, issues)) return;
  for (const key of keys) {
    if (typeof value[key] !== "boolean") issues.push(`${location}.${key} must be boolean`);
  }
}

function validDate(value) {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)
    && Number.isFinite(Date.parse(value));
}

function validateReleaseIdentity(release, location, issues, includePhase = true) {
  const fields = ["version", "build", "commit"];
  if (includePhase) {
    fields.push("rolloutChannel", "rolloutStage", "phasedReleaseDay", "phasedReleasePercent");
  }
  if (!exactKeys(release, fields, location, issues)) return;

  if (typeof release.version !== "string" || !/^\d+\.\d+\.\d+$/.test(release.version)) {
    issues.push(`${location}.version must use numeric major.minor.patch form`);
  }
  if (typeof release.build !== "string" || !/^[1-9]\d*$/.test(release.build)) {
    issues.push(`${location}.build must be a positive integer string`);
  }
  if (typeof release.commit !== "string" || !/^[0-9a-f]{40}$/.test(release.commit)) {
    issues.push(`${location}.commit must be a full lowercase Git SHA`);
  }

  if (includePhase) {
    const channels = new Set(["testflight-staged", "app-store-phased-update"]);
    if (!channels.has(release.rolloutChannel)) {
      issues.push(`${location}.rolloutChannel must be testflight-staged or app-store-phased-update`);
    } else if (release.rolloutChannel === "app-store-phased-update") {
      if (!Number.isInteger(release.phasedReleaseDay) || !PHASE_PERCENTAGES.has(release.phasedReleaseDay)) {
        issues.push(`${location}.phasedReleaseDay must be an integer from 1 through 7`);
      } else if (release.phasedReleasePercent !== PHASE_PERCENTAGES.get(release.phasedReleaseDay)) {
        issues.push(
          `${location}.phasedReleasePercent must be ${PHASE_PERCENTAGES.get(release.phasedReleaseDay)} on day ${release.phasedReleaseDay}`
        );
      }
      if (release.rolloutStage !== `day-${release.phasedReleaseDay}`) {
        issues.push(`${location}.rolloutStage must match the App Store phased-release day`);
      }
    } else {
      const stages = new Set(["internal", "external-small", "external-expanded", "candidate-complete"]);
      if (!stages.has(release.rolloutStage)) {
        issues.push(`${location}.rolloutStage is not a valid staged TestFlight cohort`);
      }
      if (release.phasedReleaseDay !== null || release.phasedReleasePercent !== null) {
        issues.push(`${location} must leave phased-release day and percentage null for TestFlight`);
      }
    }
  }
}

function validateCanary(input) {
  const issues = [];
  const topKeys = [
    "schemaVersion",
    "evidenceKind",
    "release",
    "policy",
    "approvals",
    "sources",
    "windows",
    "reviews",
  ];
  if (!exactKeys(input, topKeys, "canary", issues)) return issues;

  if (input.schemaVersion !== 1) issues.push("canary.schemaVersion must equal 1");
  if (!new Set(["production", "synthetic"]).has(input.evidenceKind)) {
    issues.push("canary.evidenceKind must be production or synthetic");
  }

  validateReleaseIdentity(input.release, "canary.release", issues);

  const policyKeys = [
    "crashFreeMinimumPercent",
    "checkCompletionMinimumPercent",
    "baselineExclusionMaximumPercent",
    "technicalInconclusiveMaximumPercent",
    "minimumRateSampleSize",
    "consecutiveBreachesRequired",
  ];
  if (exactKeys(input.policy, policyKeys, "canary.policy", issues)) {
    finiteNumber(input.policy.crashFreeMinimumPercent, "canary.policy.crashFreeMinimumPercent", issues, 0, 100);
    finiteNumber(input.policy.checkCompletionMinimumPercent, "canary.policy.checkCompletionMinimumPercent", issues, 0, 100);
    finiteNumber(input.policy.baselineExclusionMaximumPercent, "canary.policy.baselineExclusionMaximumPercent", issues, 0, 100);
    finiteNumber(input.policy.technicalInconclusiveMaximumPercent, "canary.policy.technicalInconclusiveMaximumPercent", issues, 0, 100);
    if (!Number.isInteger(input.policy.minimumRateSampleSize) || input.policy.minimumRateSampleSize < 1) {
      issues.push("canary.policy.minimumRateSampleSize must be a positive integer");
    }
    if (!Number.isInteger(input.policy.consecutiveBreachesRequired)
      || input.policy.consecutiveBreachesRequired < 2
      || input.policy.consecutiveBreachesRequired > 10) {
      issues.push("canary.policy.consecutiveBreachesRequired must be from 2 through 10");
    }
  }

  booleanFields(input.approvals, ["founder", "engineering", "privacyLegal", "qa"], "canary.approvals", issues);

  const sourceKeys = [
    "stability",
    "checkCompletion",
    "baselineExclusions",
    "technicalInconclusive",
    "supportIssues",
  ];
  if (exactKeys(input.sources, sourceKeys, "canary.sources", issues)) {
    for (const key of sourceKeys) {
      if (!AGGREGATE_SOURCES.has(input.sources[key])) {
        issues.push(`canary.sources.${key} is not an approved aggregate source`);
      }
    }
  }

  if (!Array.isArray(input.windows) || input.windows.length === 0) {
    issues.push("canary.windows must contain at least one aggregate window");
  } else {
    let priorEnd = 0;
    const seenIDs = new Set();
    input.windows.forEach((window, index) => {
      const location = `canary.windows[${index}]`;
      const windowKeys = [
        "id",
        "startsAt",
        "endsAt",
        "crashFreeSessionsPercent",
        "counts",
        "technicalInconclusiveReasons",
        "supportIssues",
        "criticalIncidents",
      ];
      if (!exactKeys(window, windowKeys, location, issues)) return;

      if (typeof window.id !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(window.id)) {
        issues.push(`${location}.id must be a lowercase aggregate-window slug`);
      } else if (seenIDs.has(window.id)) {
        issues.push(`${location}.id must be unique`);
      } else {
        seenIDs.add(window.id);
      }

      if (!validDate(window.startsAt)) issues.push(`${location}.startsAt must be an ISO-8601 UTC timestamp`);
      if (!validDate(window.endsAt)) issues.push(`${location}.endsAt must be an ISO-8601 UTC timestamp`);
      const start = Date.parse(window.startsAt);
      const end = Date.parse(window.endsAt);
      if (Number.isFinite(start) && Number.isFinite(end)) {
        if (start >= end) issues.push(`${location} must end after it starts`);
        if (index > 0 && start < priorEnd) issues.push(`${location} overlaps the preceding window`);
        priorEnd = end;
      }

      finiteNumber(window.crashFreeSessionsPercent, `${location}.crashFreeSessionsPercent`, issues, 0, 100);

      const countKeys = [
        "stabilitySampleSize",
        "checksStarted",
        "checksCompleted",
        "baselineReviewed",
        "baselineExcluded",
        "conclusionEligibleChecks",
        "technicalInconclusive",
      ];
      if (exactKeys(window.counts, countKeys, `${location}.counts`, issues)) {
        for (const key of countKeys) nonnegativeInteger(window.counts[key], `${location}.counts.${key}`, issues);
        if (window.counts.checksCompleted > window.counts.checksStarted) {
          issues.push(`${location}.counts.checksCompleted cannot exceed checksStarted`);
        }
        if (window.counts.baselineExcluded > window.counts.baselineReviewed) {
          issues.push(`${location}.counts.baselineExcluded cannot exceed baselineReviewed`);
        }
        if (window.counts.technicalInconclusive > window.counts.conclusionEligibleChecks) {
          issues.push(`${location}.counts.technicalInconclusive cannot exceed conclusionEligibleChecks`);
        }
      }

      const reasonKeys = [
        "cameraUnavailable",
        "permissionDenied",
        "captureQuality",
        "interruption",
        "taskQuality",
        "otherTechnical",
      ];
      if (exactKeys(
        window.technicalInconclusiveReasons,
        reasonKeys,
        `${location}.technicalInconclusiveReasons`,
        issues
      )) {
        for (const key of reasonKeys) {
          nonnegativeInteger(
            window.technicalInconclusiveReasons[key],
            `${location}.technicalInconclusiveReasons.${key}`,
            issues
          );
        }
        const reasonTotal = reasonKeys.reduce(
          (sum, key) => sum + window.technicalInconclusiveReasons[key],
          0
        );
        if (reasonTotal !== window.counts?.technicalInconclusive) {
          issues.push(`${location}.technicalInconclusiveReasons must sum to counts.technicalInconclusive`);
        }
      }

      const supportKeys = ["p0", "p1", "p2"];
      if (exactKeys(window.supportIssues, supportKeys, `${location}.supportIssues`, issues)) {
        for (const key of supportKeys) nonnegativeInteger(window.supportIssues[key], `${location}.supportIssues.${key}`, issues);
      }

      if (exactKeys(window.criticalIncidents, CRITICAL_INCIDENT_KEYS, `${location}.criticalIncidents`, issues)) {
        for (const key of CRITICAL_INCIDENT_KEYS) {
          nonnegativeInteger(window.criticalIncidents[key], `${location}.criticalIncidents.${key}`, issues);
        }
      }
    });
  }

  if (exactKeys(input.reviews, ["day7", "day30"], "canary.reviews", issues)) {
    for (const key of ["day7", "day30"]) {
      booleanFields(input.reviews[key], ["due", "completed", "approved"], `canary.reviews.${key}`, issues);
      if (isPlainObject(input.reviews[key])) {
        if (input.reviews[key].approved && !input.reviews[key].completed) {
          issues.push(`canary.reviews.${key} cannot be approved before completion`);
        }
      }
    }
  }

  return issues;
}

function percentage(numerator, denominator) {
  return denominator === 0 ? null : (numerator / denominator) * 100;
}

function consecutiveTailBreaches(values, predicate) {
  let count = 0;
  for (let index = values.length - 1; index >= 0; index -= 1) {
    if (!predicate(values[index])) break;
    count += 1;
  }
  return count;
}

function canaryWindowRates(window) {
  return {
    id: window.id,
    crashFreeSessionsPercent: window.crashFreeSessionsPercent,
    checkCompletionPercent: percentage(window.counts.checksCompleted, window.counts.checksStarted),
    baselineExclusionPercent: percentage(window.counts.baselineExcluded, window.counts.baselineReviewed),
    technicalInconclusivePercent: percentage(
      window.counts.technicalInconclusive,
      window.counts.conclusionEligibleChecks
    ),
    technicalInconclusiveReasons: window.technicalInconclusiveReasons,
  };
}

function evaluateCanary(input) {
  const issues = validateCanary(input);
  if (issues.length > 0) return { status: "INVALID", issues };

  const reasons = [];
  const warnings = [];
  const rates = input.windows.map(canaryWindowRates);
  const latest = input.windows.at(-1);
  const approvalsComplete = Object.values(input.approvals).every(Boolean);

  for (const window of input.windows) {
    for (const key of CRITICAL_INCIDENT_KEYS) {
      if (window.criticalIncidents[key] > 0) {
        reasons.push(`critical ${key} incident in ${window.id}`);
      }
    }
    if (window.supportIssues.p0 > 0) reasons.push(`P0 support issue in ${window.id}`);
  }

  if (reasons.length > 0) {
    return {
      schemaVersion: 1,
      evidenceKind: input.evidenceKind,
      status: "PAUSE",
      release: input.release,
      rates,
      reasons,
      warnings,
      reviews: input.reviews,
    };
  }

  if (input.evidenceKind !== "production") warnings.push("synthetic evidence cannot authorize a rollout");
  if (!approvalsComplete) warnings.push("rollout policy approvals are incomplete");
  if (input.windows.some((window) => window.supportIssues.p1 > 0)) {
    warnings.push("a P1 support issue is open");
  }

  for (const key of ["day7", "day30"]) {
    const review = input.reviews[key];
    if (review.due && (!review.completed || !review.approved)) {
      warnings.push(`${key} review is due but not completed and approved`);
    }
  }

  const minimum = input.policy.minimumRateSampleSize;
  const required = input.policy.consecutiveBreachesRequired;
  const sampleChecks = [
    [latest.counts.stabilitySampleSize, "stability"],
    [latest.counts.checksStarted, "check completion"],
    [latest.counts.baselineReviewed, "baseline exclusion"],
    [latest.counts.conclusionEligibleChecks, "technical inconclusive"],
  ];
  for (const [sampleSize, label] of sampleChecks) {
    if (sampleSize < minimum) warnings.push(`${label} sample is ${sampleSize}; policy requires ${minimum}`);
  }

  const stabilityBreaches = consecutiveTailBreaches(
    input.windows,
    (window) => window.counts.stabilitySampleSize >= minimum
      && window.crashFreeSessionsPercent < input.policy.crashFreeMinimumPercent
  );
  if (stabilityBreaches >= required) {
    return {
      schemaVersion: 1,
      evidenceKind: input.evidenceKind,
      status: "PAUSE",
      release: input.release,
      rates,
      reasons: [`crash-free sessions missed policy for ${stabilityBreaches} consecutive windows`],
      warnings,
      reviews: input.reviews,
    };
  }

  const qualityMetrics = [
    {
      label: "check completion",
      breaches: consecutiveTailBreaches(
        input.windows,
        (window) => window.counts.checksStarted >= minimum
          && percentage(window.counts.checksCompleted, window.counts.checksStarted)
            < input.policy.checkCompletionMinimumPercent
      ),
    },
    {
      label: "baseline exclusion",
      breaches: consecutiveTailBreaches(
        input.windows,
        (window) => window.counts.baselineReviewed >= minimum
          && percentage(window.counts.baselineExcluded, window.counts.baselineReviewed)
            > input.policy.baselineExclusionMaximumPercent
      ),
    },
    {
      label: "technical inconclusive",
      breaches: consecutiveTailBreaches(
        input.windows,
        (window) => window.counts.conclusionEligibleChecks >= minimum
          && percentage(window.counts.technicalInconclusive, window.counts.conclusionEligibleChecks)
            > input.policy.technicalInconclusiveMaximumPercent
      ),
    },
  ];
  for (const metric of qualityMetrics) {
    if (metric.breaches >= required) {
      warnings.push(`${metric.label} missed policy for ${metric.breaches} consecutive windows`);
    }
  }

  const status = warnings.length === 0 ? "CONTINUE" : "HOLD";
  return {
    schemaVersion: 1,
    evidenceKind: input.evidenceKind,
    status,
    release: input.release,
    rates,
    reasons,
    warnings,
    reviews: input.reviews,
  };
}

function validateFinalEvidence(input) {
  const issues = [];
  const topKeys = ["schemaVersion", "evidenceKind", "candidate", "gates", "signoffs", "evidence"];
  if (!exactKeys(input, topKeys, "final", issues)) return issues;

  if (input.schemaVersion !== 1) issues.push("final.schemaVersion must equal 1");
  if (!new Set(["production", "template"]).has(input.evidenceKind)) {
    issues.push("final.evidenceKind must be production or template");
  }

  if (exactKeys(
    input.candidate,
    ["version", "build", "commit", "bundleIdentifier", "archiveSHA256"],
    "final.candidate",
    issues
  )) {
    validateReleaseIdentity(
      { version: input.candidate.version, build: input.candidate.build, commit: input.candidate.commit },
      "final.candidate",
      issues,
      false
    );
    if (input.candidate.bundleIdentifier !== "com.soberprototype.app") {
      issues.push("final.candidate.bundleIdentifier must identify the public Sober target");
    }
    if (typeof input.candidate.archiveSHA256 !== "string"
      || !/^[0-9a-f]{64}$/.test(input.candidate.archiveSHA256)) {
      issues.push("final.candidate.archiveSHA256 must be a lowercase SHA-256 digest");
    }
  }

  booleanFields(input.gates, FINAL_GATE_KEYS, "final.gates", issues);
  booleanFields(input.signoffs, SIGNOFF_KEYS, "final.signoffs", issues);

  const evidenceKeys = [
    "phase4ChecklistPath",
    "phase5ChecklistPath",
    "phase6CanaryReportPath",
    "archiveAppPath",
    "privacyPolicyURL",
    "supportURL",
    "appStoreConnectBuildURL",
  ];
  if (exactKeys(input.evidence, evidenceKeys, "final.evidence", issues)) {
    for (const key of [
      "phase4ChecklistPath",
      "phase5ChecklistPath",
      "phase6CanaryReportPath",
      "archiveAppPath",
    ]) {
      const value = input.evidence[key];
      if (typeof value !== "string" || value.length === 0 || path.isAbsolute(value) || value.includes("..")) {
        issues.push(`final.evidence.${key} must be a nonempty repository-relative path without traversal`);
      }
    }
    for (const key of ["privacyPolicyURL", "supportURL", "appStoreConnectBuildURL"]) {
      try {
        const url = new URL(input.evidence[key]);
        if (url.protocol !== "https:") issues.push(`final.evidence.${key} must use HTTPS`);
        if (input.evidenceKind === "production"
          && (url.hostname.endsWith(".invalid") || url.hostname === "localhost")) {
          issues.push(`final.evidence.${key} must be a live URL, not a placeholder`);
        }
      } catch {
        issues.push(`final.evidence.${key} must be a valid HTTPS URL`);
      }
    }
  }

  return issues;
}

function evaluateFinalReadiness(input, context = {}) {
  const issues = validateFinalEvidence(input);
  if (issues.length > 0) return { status: "INVALID", issues };

  const blockers = [];
  if (input.evidenceKind !== "production") blockers.push("template evidence cannot authorize release closure");
  for (const key of FINAL_GATE_KEYS) {
    if (!input.gates[key]) blockers.push(`gate is incomplete: ${key}`);
  }
  for (const key of SIGNOFF_KEYS) {
    if (!input.signoffs[key]) blockers.push(`signoff is incomplete: ${key}`);
  }

  if (context.expectedCommit && input.candidate.commit !== context.expectedCommit) {
    blockers.push(`candidate commit does not match HEAD ${context.expectedCommit}`);
  }
  if (context.cleanWorktree === false) blockers.push("Git worktree is not clean");

  const pathExists = context.pathExists ?? ((relativePath) => fs.existsSync(path.resolve(relativePath)));
  for (const key of [
    "phase4ChecklistPath",
    "phase5ChecklistPath",
    "phase6CanaryReportPath",
    "archiveAppPath",
  ]) {
    if (!pathExists(input.evidence[key])) blockers.push(`evidence file does not exist: ${input.evidence[key]}`);
  }

  if (pathExists(input.evidence.archiveAppPath)) {
    if (!context.inspectArchive) {
      blockers.push("archived app inspection is unavailable");
    } else {
      try {
        const archive = context.inspectArchive(input.evidence.archiveAppPath);
        const comparisons = {
          version: archive.version,
          build: archive.build,
          bundleIdentifier: archive.bundleIdentifier,
          archiveSHA256: archive.binarySHA256,
        };
        for (const [key, value] of Object.entries(comparisons)) {
          if (value !== input.candidate[key]) blockers.push(`archived app ${key} does not match candidate evidence`);
        }
      } catch (error) {
        blockers.push(`archived app could not be inspected: ${error.message}`);
      }
    }
  }

  if (pathExists(input.evidence.phase6CanaryReportPath)) {
    if (!context.readJson) {
      blockers.push("Phase 6 canary report inspection is unavailable");
    } else {
      try {
        const report = context.readJson(input.evidence.phase6CanaryReportPath);
        if (report.status !== "CONTINUE" || report.evidenceKind !== "production") {
          blockers.push("Phase 6 canary report is not an eligible CONTINUE verdict");
        }
        for (const key of ["version", "build", "commit"]) {
          if (report.release?.[key] !== input.candidate[key]) {
            blockers.push(`Phase 6 report ${key} does not match the final candidate`);
          }
        }
        if (!report.reviews?.day7?.approved || !report.reviews?.day30?.approved) {
          blockers.push("Phase 6 report lacks approved 7-day and 30-day reviews");
        }
      } catch (error) {
        blockers.push(`Phase 6 canary report could not be read: ${error.message}`);
      }
    }
  }

  return {
    schemaVersion: 1,
    evidenceKind: input.evidenceKind,
    status: blockers.length === 0 ? "READY" : "BLOCKED",
    candidate: input.candidate,
    blockers,
  };
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function repositoryContext() {
  const expectedCommit = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  const cleanWorktree = execFileSync("git", ["status", "--porcelain"], { encoding: "utf8" }).trim() === "";
  return {
    expectedCommit,
    cleanWorktree,
    pathExists: (relativePath) => fs.existsSync(path.resolve(relativePath)),
    readJson,
    inspectArchive: (relativePath) => {
      const appPath = path.resolve(relativePath);
      const infoPath = path.join(appPath, "Info.plist");
      const binaryPath = path.join(appPath, "Sober");
      const plistValue = (key) => execFileSync(
        "/usr/libexec/PlistBuddy",
        ["-c", `Print :${key}`, infoPath],
        { encoding: "utf8" }
      ).trim();
      const binarySHA256 = crypto.createHash("sha256").update(fs.readFileSync(binaryPath)).digest("hex");
      return {
        version: plistValue("CFBundleShortVersionString"),
        build: plistValue("CFBundleVersion"),
        bundleIdentifier: plistValue("CFBundleIdentifier"),
        binarySHA256,
      };
    },
  };
}

function usage() {
  console.error("Usage: node Scripts/release-ops.mjs <canary|final> INPUT.json [--output OUTPUT.json]");
}

function runCLI(argv) {
  const [command, inputPath, ...rest] = argv;
  if (!new Set(["canary", "final"]).has(command) || !inputPath) {
    usage();
    return 1;
  }

  let outputPath;
  if (rest.length > 0) {
    if (rest.length !== 2 || rest[0] !== "--output") {
      usage();
      return 1;
    }
    outputPath = rest[1];
  }

  let input;
  try {
    input = readJson(inputPath);
  } catch (error) {
    console.error(`Could not read ${inputPath}: ${error.message}`);
    return 1;
  }

  const report = command === "canary"
    ? evaluateCanary(input)
    : evaluateFinalReadiness(input, repositoryContext());
  const rendered = `${JSON.stringify(report, null, 2)}\n`;
  process.stdout.write(rendered);

  if (outputPath) {
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, rendered, { flag: "wx" });
  }

  if (report.status === "CONTINUE" || report.status === "READY") return 0;
  if (report.status === "PAUSE") return 3;
  if (report.status === "HOLD" || report.status === "BLOCKED") return 2;
  return 1;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) process.exitCode = runCLI(process.argv.slice(2));

export {
  evaluateCanary,
  evaluateFinalReadiness,
  validateCanary,
  validateFinalEvidence,
};
