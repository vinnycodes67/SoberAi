import SwiftUI

/// Colours of the things a person is measured against.
///
/// **These are instrument calibration, not theme.** The reaction task asks
/// someone to discriminate colour and shape under time pressure; the tracking
/// and gaze tasks ask them to follow a lit target. Change the hue, luminance, or
/// size of any of it and you change the measurement — reaction latency, error
/// rate, pursuit error, and pupil response all move with stimulus appearance.
///
/// A baseline recorded under one stimulus is not comparable to a check recorded
/// under another. Since the whole product is a comparison against a person's own
/// stored baseline, restyling these values silently invalidates the comparison
/// while the UI continues to claim it is comparing like with like.
///
/// So they are literals, deliberately not derived from `Palette` or `DSPalette`.
/// The DesignKit migration retinted the app's chrome by repointing `Palette` at
/// the new tokens; had the stimuli been drawn from the same source, that
/// cosmetic change would have collapsed the reaction task's two choice colours
/// into a single orange and made a colour-discrimination task undiscriminable.
///
/// > Changing anything in this file requires bumping the protocol variant and
/// > segmenting or invalidating existing baselines. It is not a design decision.
enum StimulusPalette {

  /// The "Blue" choice in the six-choice reaction task, and the lit target in
  /// the tracking and ocular tasks.
  static let targetPrimary = Color(hue: 0.5500, saturation: 0.700, brightness: 0.610)

  /// The contrasting choice in the reaction task. Must remain clearly separable
  /// from `targetPrimary` for someone with normal colour vision under low light.
  static let targetContrast = Color(hue: 0.9670, saturation: 0.700, brightness: 0.810)

  /// The neutral field a stimulus is presented on.
  static let field = Color(hue: 0.5500, saturation: 0.120, brightness: 0.140)

  /// Dimmed guides that are visible but never the target.
  static let guide = Color(hue: 0.5500, saturation: 0.220, brightness: 0.510)
}
