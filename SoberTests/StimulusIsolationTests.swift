import SwiftUI
import XCTest

@testable import Sober

/// The stimulus must not be reachable from the theme.
///
/// The DesignKit migration repointed `Palette` at `DSPalette`, where the old
/// `primary` (cyan) and `accent` (magenta) both became the single orange. The
/// six-choice reaction task colours its two choices with exactly those two
/// names, so a purely cosmetic change made a colour-discrimination task
/// undiscriminable — and every task stimulus silently changed hue and luminance,
/// which invalidates comparison against baselines recorded before the change.
///
/// These tests fail if the stimulus is ever wired back to the theme.
final class StimulusIsolationTests: XCTestCase {

  private func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b)
  }

  private func assertDistinct(
    _ lhs: Color,
    _ rhs: Color,
    minimumSeparation: CGFloat = 0.2,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let a = components(lhs)
    let b = components(rhs)
    let distance = ((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))
      .squareRoot()
    XCTAssertGreaterThan(distance, minimumSeparation, message, file: file, line: line)
  }

  /// The task asks someone to tell these apart under time pressure. If they
  /// converge, error rate stops measuring perception and starts measuring the
  /// palette.
  func testReactionChoiceColoursAreDistinguishable() {
    assertDistinct(
      StimulusPalette.targetPrimary,
      StimulusPalette.targetContrast,
      "the two reaction-task choice colours must remain separable"
    )
  }

  /// The specific failure that shipped for one build: both choices resolving
  /// through a theme whose primary and accent are now the same value.
  func testStimulusIsNotDrawnFromTheAppTheme() {
    assertDistinct(
      StimulusPalette.targetPrimary,
      Palette.primary,
      "stimulus must not follow the theme's primary"
    )
    assertDistinct(
      StimulusPalette.targetContrast,
      Palette.accent,
      "stimulus must not follow the theme's accent"
    )
  }

  /// A target has to stand off the field it is presented on, and the dim guides
  /// must never be mistakable for the target.
  func testTargetSeparatesFromFieldAndGuides() {
    assertDistinct(
      StimulusPalette.targetPrimary,
      StimulusPalette.field,
      "the target must stand off its field"
    )
    assertDistinct(
      StimulusPalette.targetPrimary,
      StimulusPalette.guide,
      "guides must not read as the target"
    )
  }

  /// Pins the measured values. Changing them is a protocol change that requires
  /// segmenting or invalidating stored baselines, so it should not be possible
  /// to do by accident while restyling a screen.
  func testStimulusValuesArePinnedToTheCalibratedProtocol() {
    let target = components(StimulusPalette.targetPrimary)
    let contrast = components(StimulusPalette.targetContrast)

    XCTAssertEqual(Double(target.r), 0.183, accuracy: 0.01)
    XCTAssertEqual(Double(target.g), 0.482, accuracy: 0.01)
    XCTAssertEqual(Double(target.b), 0.610, accuracy: 0.01)

    XCTAssertEqual(Double(contrast.r), 0.810, accuracy: 0.01)
    XCTAssertEqual(Double(contrast.g), 0.243, accuracy: 0.01)
    XCTAssertEqual(Double(contrast.b), 0.355, accuracy: 0.01)
  }
}
