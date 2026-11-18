import CoreGraphics
import Foundation

/// An affine map from raw screen gaze to where the person was really looking,
/// both in portrait screen points.
struct ScreenAffineMap: Equatable, Sendable {
  var xx: Double
  var xy: Double
  var x0: Double
  var yx: Double
  var yy: Double
  var y0: Double

  func apply(x: Double, y: Double) -> (x: Double, y: Double) {
    (xx * x + xy * y + x0, yx * x + yy * y + y0)
  }
}

/// One capture's follow-the-dot calibration. Held in memory from the end of
/// calibration to the end of the protocol it precedes; only `metrics` is
/// stored with the session.
struct OcularCalibration: Equatable, Sendable {
  var metrics: OcularCalibrationMetrics
  /// Nil when too few points were usable to fit.
  var map: ScreenAffineMap?
  /// Where the eye-in-head gaze settled at each kept point: the same points
  /// the saccade phase supplies for pursuit gain's scale.
  var eyeInHeadPoints: [OcularDetailedAnalyzer.CalibrationPoint]
  /// The stimulus field in screen points, which turns a target's 0-1 position
  /// into a place on the display. Nil when the view could not supply it.
  var field: CGRect?
}

/// Fits `OcularCalibration` from the calibration step's samples.
///
/// Per point, the samples in the scored part of its second are taken, using
/// the same validity labels as the detailed measures (eyes open, head still,
/// plausible vectors). Samples far from their point's median are dropped,
/// then an affine map from raw screen gaze to the dot is fitted by least
/// squares through the points' medians. One whole point is dropped when the
/// other points agree the person did not look at it.
///
/// Every threshold here is an engineering guess made before any real capture
/// was looked at (HANDOFF 2.6). The result only ever marks a capture
/// *degraded*: whether a capture counts is still `CaptureQualitySnapshot.isUsable`.
enum OcularCalibrationFitter {
  /// About a third of the samples 60 Hz delivers in the scored 0.6 s.
  static let minimumSamplesPerPoint = 12
  /// A scored sample further than this many scaled median absolute
  /// deviations from its point's median is a glance away, not noise.
  static let sampleOutlierMADs = 3.0
  /// Never reject a sample closer to its point's median than this.
  static let sampleOutlierFloorMillimetres = 1.0
  /// An affine map through three points fits them exactly and proves
  /// nothing, so calibration needs four.
  static let minimumPoints = 4
  /// ENGINEERING GUESS (HANDOFF 1.13): the quality bar. The calibration
  /// points sit only about 3 degrees from the centre at 40 cm, so someone who
  /// never follows the dot scores about 2.7 degrees; the bar has to sit well
  /// under that. Real ARKit gaze noise has not been measured.
  static let maximumResidualDegrees = 1.0
  /// One point is dropped when it sits this many times further from where
  /// the other points put it than their own residual, and further than the
  /// bar. Judged against the other points, not only the bar: at arm's length
  /// the whole pattern spans a couple of degrees, so a fit pulled off by one
  /// missed point can still come in under the bar.
  static let pointOutlierFactor = 3.0

  private struct Scored {
    var gazeX: Double
    var gazeY: Double
    var distance: Double
  }

  private struct FittedPoint {
    var index: Int
    var targetX: Double
    var targetY: Double
    var medianX: Double
    var medianY: Double
    var kept: [Scored]
  }

  /// `startedAt` is on the samples' clock. `field` and `display` place the
  /// targets on the screen; without either there is no screen fit.
  static func fit(
    samples: [OcularSample],
    startedAt: TimeInterval,
    field: CGRect?,
    display: DisplayGeometry?
  ) -> OcularCalibration {
    let schedule = OcularCalibrationSchedule.self
    let calibration = samples
      .filter { $0.phase == .calibration && $0.timestamp.isFinite }
      .sorted { $0.timestamp < $1.timestamp }
    let labels = OcularDetailedAnalyzer.labels(for: calibration)

    var eyeInHead = [[(x: Double, y: Double)]](repeating: [], count: schedule.points.count)
    var screen = [[Scored]](repeating: [], count: schedule.points.count)
    for (sample, label) in zip(calibration, labels) where label == .valid {
      let elapsed = sample.timestamp - startedAt
      guard let index = schedule.pointIndex(at: elapsed), schedule.isScored(at: elapsed) else { continue }
      eyeInHead[index].append((
        (sample.leftGazeX + sample.rightGazeX) / 2, (sample.leftGazeY + sample.rightGazeY) / 2))
      if let x = sample.screenGazeX, let y = sample.screenGazeY,
        let distance = sample.screenViewingDistanceMetres,
        x.isFinite, y.isFinite, distance.isFinite, distance > 0
      {
        screen[index].append(Scored(gazeX: x, gazeY: y, distance: distance))
      }
    }

    var eyeInHeadPoints: [Int: OcularDetailedAnalyzer.CalibrationPoint] = [:]
    for (index, values) in eyeInHead.enumerated() where values.count >= minimumSamplesPerPoint {
      guard let x = OcularDetailedAnalyzer.median(values.map(\.x)),
        let y = OcularDetailedAnalyzer.median(values.map(\.y))
      else { continue }
      eyeInHeadPoints[index] = .init(
        targetX: schedule.points[index].x, targetY: schedule.points[index].y, x: x, y: y)
    }

    func result(
      used: [FittedPoint], map: ScreenAffineMap?, residual: Double?, rejected: Double?
    ) -> OcularCalibration {
      let indices = Set(used.map(\.index))
      let passed = used.count >= minimumPoints && (residual.map { $0 <= maximumResidualDegrees } ?? false)
      return OcularCalibration(
        metrics: OcularCalibrationMetrics(
          pointsScheduled: schedule.points.count,
          pointsUsed: used.count,
          residualRMSDegrees: residual,
          viewingDistanceMetres: OcularDetailedAnalyzer.median(used.flatMap { $0.kept.map(\.distance) }),
          rejectedSampleFraction: rejected,
          passed: passed),
        map: map,
        // A point the screen fit threw out is not trusted for scale either.
        eyeInHeadPoints: eyeInHeadPoints.keys.sorted()
          .filter { map == nil || indices.contains($0) }
          .compactMap { eyeInHeadPoints[$0] },
        field: field)
    }

    guard let field, let display, field.width > 0, field.height > 0,
      field.width.isFinite, field.height.isFinite, field.minX.isFinite, field.minY.isFinite
    else { return result(used: [], map: nil, residual: nil, rejected: nil) }

    // Per point: drop glances away, then take the median of what is left.
    let floor = sampleOutlierFloorMillimetres * display.pointsPerMillimetre
    var points: [FittedPoint] = []
    var scoredCount = 0
    var keptCount = 0
    for (index, values) in screen.enumerated() where values.count >= minimumSamplesPerPoint {
      guard let centreX = OcularDetailedAnalyzer.median(values.map(\.gazeX)),
        let centreY = OcularDetailedAnalyzer.median(values.map(\.gazeY))
      else { continue }
      let distances = values.map { hypot($0.gazeX - centreX, $0.gazeY - centreY) }
      let spread = 1.4826 * (OcularDetailedAnalyzer.median(distances) ?? 0)
      let cutoff = max(sampleOutlierMADs * spread, floor)
      let kept = zip(values, distances).filter { $0.1 <= cutoff }.map(\.0)
      scoredCount += values.count
      guard kept.count >= minimumSamplesPerPoint,
        let medianX = OcularDetailedAnalyzer.median(kept.map(\.gazeX)),
        let medianY = OcularDetailedAnalyzer.median(kept.map(\.gazeY))
      else { continue }
      keptCount += kept.count
      points.append(FittedPoint(
        index: index,
        targetX: Double(field.minX) + schedule.points[index].x * Double(field.width),
        targetY: Double(field.minY) + schedule.points[index].y * Double(field.height),
        medianX: medianX, medianY: medianY, kept: kept))
    }
    let rejected = scoredCount > 0 ? 1 - Double(keptCount) / Double(scoredCount) : nil

    guard points.count >= minimumPoints, let map = affine(through: points),
      let residual = residualDegrees(of: map, over: points, display: display)
    else { return result(used: points, map: nil, residual: nil, rejected: rejected) }

    // One point the person did not look at.
    if points.count > minimumPoints {
      var best: (points: [FittedPoint], map: ScreenAffineMap, residual: Double)?
      for dropped in points.indices {
        var remaining = points
        let outlier = remaining.remove(at: dropped)
        guard let candidate = affine(through: remaining),
          let candidateResidual = residualDegrees(of: candidate, over: remaining, display: display),
          candidateResidual < residual,
          let miss = medianErrorDegrees(of: candidate, at: outlier, display: display),
          miss > max(pointOutlierFactor * candidateResidual, maximumResidualDegrees),
          candidateResidual < (best?.residual ?? .infinity)
        else { continue }
        best = (remaining, candidate, candidateResidual)
      }
      if let best {
        return result(used: best.points, map: best.map, residual: best.residual, rejected: rejected)
      }
    }
    return result(used: points, map: map, residual: residual, rejected: rejected)
  }

  // MARK: - Least squares

  /// Least-squares affine map taking each point's median gaze to its target.
  /// Nil when the gaze medians do not span two directions.
  private static func affine(through points: [FittedPoint]) -> ScreenAffineMap? {
    let n = Double(points.count)
    guard points.count >= 3 else { return nil }
    let meanX = points.reduce(0) { $0 + $1.medianX } / n
    let meanY = points.reduce(0) { $0 + $1.medianY } / n
    let meanTargetX = points.reduce(0) { $0 + $1.targetX } / n
    let meanTargetY = points.reduce(0) { $0 + $1.targetY } / n
    var uu = 0.0, uv = 0.0, vv = 0.0
    var uTargetX = 0.0, vTargetX = 0.0, uTargetY = 0.0, vTargetY = 0.0
    for point in points {
      let u = point.medianX - meanX
      let v = point.medianY - meanY
      uu += u * u
      uv += u * v
      vv += v * v
      uTargetX += u * (point.targetX - meanTargetX)
      vTargetX += v * (point.targetX - meanTargetX)
      uTargetY += u * (point.targetY - meanTargetY)
      vTargetY += v * (point.targetY - meanTargetY)
    }
    let determinant = uu * vv - uv * uv
    let scale = uu + vv
    guard scale.isFinite, scale > 0, determinant.isFinite, determinant > 1e-9 * scale * scale
    else { return nil }
    let xx = (vv * uTargetX - uv * vTargetX) / determinant
    let xy = (uu * vTargetX - uv * uTargetX) / determinant
    let yx = (vv * uTargetY - uv * vTargetY) / determinant
    let yy = (uu * vTargetY - uv * uTargetY) / determinant
    let map = ScreenAffineMap(
      xx: xx, xy: xy, x0: meanTargetX - xx * meanX - xy * meanY,
      yx: yx, yy: yy, y0: meanTargetY - yx * meanX - yy * meanY)
    return [map.xx, map.xy, map.x0, map.yx, map.yy, map.y0].allSatisfy(\.isFinite) ? map : nil
  }

  /// A distance on the screen, in points, as an angle at the eye.
  private static func degrees(points: Double, distanceMetres: Double, display: DisplayGeometry) -> Double {
    atan2(points / display.pointsPerMillimetre / 1_000, distanceMetres) * 180 / .pi
  }

  /// RMS over every kept sample, so it carries both how well the map fits
  /// the points and how steady the gaze was on each.
  private static func residualDegrees(
    of map: ScreenAffineMap, over points: [FittedPoint], display: DisplayGeometry
  ) -> Double? {
    var sum = 0.0
    var count = 0
    for point in points {
      for sample in point.kept {
        let mapped = map.apply(x: sample.gazeX, y: sample.gazeY)
        let error = degrees(
          points: hypot(mapped.x - point.targetX, mapped.y - point.targetY),
          distanceMetres: sample.distance, display: display)
        sum += error * error
        count += 1
      }
    }
    guard count > 0 else { return nil }
    return OcularDetailedAnalyzer.finite((sum / Double(count)).squareRoot())
  }

  private static func medianErrorDegrees(
    of map: ScreenAffineMap, at point: FittedPoint, display: DisplayGeometry
  ) -> Double? {
    guard let distance = OcularDetailedAnalyzer.median(point.kept.map(\.distance)) else { return nil }
    let mapped = map.apply(x: point.medianX, y: point.medianY)
    return OcularDetailedAnalyzer.finite(degrees(
      points: hypot(mapped.x - point.targetX, mapped.y - point.targetY),
      distanceMetres: distance, display: display))
  }
}
