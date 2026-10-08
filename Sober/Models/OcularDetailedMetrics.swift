import Foundation

/// What a single eye-task sample is good for. Assigned per sample before any
/// detailed measure is computed; only `valid` samples feed those measures.
enum OcularSampleValidity: String, Codable, CaseIterable, Sendable {
  case valid
  /// Measured, but implausible or next to a blink: not trusted for timing.
  case lowConfidence
  /// Blink blendshapes say the lids were closed. Missing blendshapes never
  /// produce this label: no telemetry is not evidence of a closed eye.
  case eyesClosed
  /// The head turned fast enough that eye-in-head angles stop following the
  /// target (the eyes counter-rotate against the head).
  case headMoved
  /// ARKit returned no usable eye vector (non-finite or zero).
  case missing
}

/// Richer eye-task measures, recorded on every capture so they can be judged
/// against real sessions later. Nothing here is scored: `smoothnessRisk` and
/// `isUsable` are computed exactly as before, and baselines never read this.
///
/// These are engineering measures of what ARKit's eye vectors did, not
/// clinical ones. Angles come from ARKit's eye-in-head forward vectors, whose
/// x and y components are read as radians (small-angle approximation) and
/// reported in approximate degrees.
///
/// Every phase measure carries the share of its scheduled time covered by
/// valid samples. A phase below `OcularDetailedAnalyzer.minimumPhaseCoverage`
/// is nil rather than zero, so an absent measurement can never read as a
/// perfect or terrible one.
struct OcularDetailedMetrics: Codable, Equatable, Sendable {
  static let currentVersion = 1

  /// Bumped whenever a definition or threshold changes, so values recorded
  /// under different rules are never pooled.
  var version: Int
  var validity: OcularValidityFractions
  var coverage: OcularPhaseCoverage
  var fixation: OcularFixationMetrics?
  var horizontalPursuit: OcularPursuitMetrics?
  var verticalPursuit: OcularPursuitMetrics?
  var saccades: OcularSaccadeMetrics?
  /// Saccades detected anywhere in the protocol's valid samples.
  var gazeTransitionCount: Int?
  var gazeTransitionsPerMinute: Double?
  var binocular: OcularBinocularMetrics?
  /// Same events and threshold as `OcularSignalFeatures.blinkRatePerMinute`.
  /// Nil when no sample carried blink telemetry.
  var blinkCount: Int?
  var blinkRatePerMinute: Double?
}

/// Fraction of protocol samples (calibration excluded) given each label. They
/// sum to 1 when `sampleCount` is above zero.
struct OcularValidityFractions: Codable, Equatable, Sendable {
  var sampleCount: Int
  var valid: Double
  var lowConfidence: Double
  var eyesClosed: Double
  var headMoved: Double
  var missing: Double
  /// Samples with no blink blendshape at all. They are not labelled closed,
  /// but they are not confirmed open either.
  var eyeStateUnknown: Double
}

/// Valid-sample time as a fraction of each phase's scheduled duration. Nil
/// for a phase the protocol variant does not run.
struct OcularPhaseCoverage: Codable, Equatable, Sendable {
  var fixation: Double?
  var horizontalPursuit: Double?
  var verticalPursuit: Double?
  var saccades: Double?
}

struct OcularFixationMetrics: Codable, Equatable, Sendable {
  var coverage: Double
  /// Root-mean-square distance of gaze from its mean, approximate degrees.
  var dispersionRMSDegrees: Double?
  /// Bivariate contour ellipse area holding 68% of gaze points, square degrees.
  var bceaSquareDegrees: Double?
  /// Longest unbroken run of valid samples with no saccade, in ms.
  var longestStableMilliseconds: Double?
  /// Saccades while the target held still.
  var intrusiveSaccadeCount: Int
}

struct OcularPursuitMetrics: Codable, Equatable, Sendable {
  var coverage: Double
  /// Eye velocity over target velocity with saccades removed. Nil when the
  /// saccade phase could not supply the gaze-to-screen scale it needs.
  var gain: Double?
  /// Delay that best aligns gaze with the target, by cross-correlation.
  /// Positive means the eyes trail the target.
  var lagMilliseconds: Double?
  var catchUpSaccadeCount: Int
}

struct OcularSaccadeMetrics: Codable, Equatable, Sendable {
  var coverage: Double
  /// Target jumps seen in the samples.
  var jumpCount: Int
  /// Jumps with enough valid samples around them to judge.
  var analysedJumpCount: Int
  /// Share of analysed jumps followed by a detected eye movement toward the
  /// new target.
  var respondedFraction: Double?
  var medianLatencyMilliseconds: Double?
  /// First saccade's travel along the jump over where the eyes settled. Above
  /// 1 overshoots, below 1 undershoots. Calibration-free.
  var medianPrimaryGain: Double?
  /// Distance from the first saccade's landing to where the eyes settled, as
  /// a fraction of the jump.
  var medianLandingError: Double?
  var correctiveSaccadeCount: Int
  var jumps: [OcularSaccadeJump]
}

struct OcularSaccadeJump: Codable, Equatable, Sendable {
  var responded: Bool
  var latencyMilliseconds: Double?
  var primaryGain: Double?
  var landingError: Double?
  var correctiveSaccadeCount: Int
}

struct OcularBinocularMetrics: Codable, Equatable, Sendable {
  /// Mean of the per-axis Pearson correlations of left and right gaze. Nil
  /// when neither axis moved enough to correlate.
  var leftRightCorrelation: Double?
  /// RMS of left-minus-right gaze around its mean, so a constant vergence
  /// offset does not count. Approximate degrees.
  var disagreementRMSDegrees: Double?
}
