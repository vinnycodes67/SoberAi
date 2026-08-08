import Foundation

/// Pure measurement helpers retained for research analysis. The camera-driven
/// pupillometry experiment is not part of the shipping flow until its trained
/// segmentation model and an approved task screen are available.
enum EllipseFit {
  struct Result {
    let majorAxis: Double
    let minorAxis: Double
    var averageDiameter: Double { (majorAxis + minorAxis) / 2 }
  }

  static func fit(points: [(x: Double, y: Double)]) -> Result? {
    guard points.count >= 8 else { return nil }
    let n = Double(points.count)
    let meanX = points.reduce(0) { $0 + $1.x } / n
    let meanY = points.reduce(0) { $0 + $1.y } / n

    var cxx = 0.0
    var cyy = 0.0
    var cxy = 0.0
    for point in points {
      let dx = point.x - meanX
      let dy = point.y - meanY
      cxx += dx * dx
      cyy += dy * dy
      cxy += dx * dy
    }
    cxx /= n
    cyy /= n
    cxy /= n

    let trace = cxx + cyy
    let determinant = cxx * cyy - cxy * cxy
    let discriminant = max(trace * trace / 4 - determinant, 0)
    let sqrtDiscriminant = discriminant.squareRoot()
    let lambda1 = trace / 2 + sqrtDiscriminant
    let lambda2 = max(trace / 2 - sqrtDiscriminant, 0)

    // For a uniformly filled ellipse, semi-axis length = 2 × √eigenvalue.
    let semiMajor = 2 * lambda1.squareRoot()
    let semiMinor = 2 * lambda2.squareRoot()
    return Result(majorAxis: semiMajor * 2, minorAxis: semiMinor * 2)
  }
}

enum PupilLightReflexAnalyzer {
  static func deriveTrial(
    samples: [(timestamp: TimeInterval, diameterMm: Double)],
    flashOnsetTime: TimeInterval?
  ) -> PupilLightReflexTrial? {
    guard let flashOnsetTime, samples.count >= 8 else { return nil }

    let preFlash = samples.filter { $0.timestamp < flashOnsetTime }
    let postFlash = samples.filter { $0.timestamp >= flashOnsetTime }
      .sorted { $0.timestamp < $1.timestamp }
    guard preFlash.count >= 4, postFlash.count >= 4 else { return nil }

    let baselineWindow = preFlash.filter { $0.timestamp >= flashOnsetTime - 2 }
    let baselineSet = baselineWindow.isEmpty ? preFlash : baselineWindow
    let baselineDiameter = baselineSet.map(\.diameterMm).reduce(0, +) / Double(baselineSet.count)

    guard let minSample = postFlash.min(by: { $0.diameterMm < $1.diameterMm }) else { return nil }
    let minDiameter = minSample.diameterMm

    let onsetThreshold = baselineDiameter * 0.95
    let onsetSample = postFlash.first { $0.diameterMm <= onsetThreshold }
    let latency = max((onsetSample?.timestamp ?? minSample.timestamp) - flashOnsetTime, 0)

    let constrictionPhase = postFlash.filter { $0.timestamp <= minSample.timestamp }
    var peakVelocity = 0.0
    if constrictionPhase.count >= 2 {
      for index in 1..<constrictionPhase.count {
        let previous = constrictionPhase[index - 1]
        let current = constrictionPhase[index]
        let delta = current.timestamp - previous.timestamp
        guard delta > 0 else { continue }
        peakVelocity = max(peakVelocity, (previous.diameterMm - current.diameterMm) / delta)
      }
    }

    let amplitude = baselineDiameter > 0
      ? min(max((baselineDiameter - minDiameter) / baselineDiameter, 0), 1)
      : 0
    let recoveryTarget = minDiameter + 0.75 * (baselineDiameter - minDiameter)
    let recoverySample = postFlash.first {
      $0.timestamp >= minSample.timestamp && $0.diameterMm >= recoveryTarget
    }

    return PupilLightReflexTrial(
      baselineDiameterMm: baselineDiameter,
      minDiameterMm: minDiameter,
      latencySeconds: latency,
      peakConstrictionVelocityMmPerSecond: peakVelocity,
      amplitudePercent: amplitude,
      recoveryTo75PercentSeconds: recoverySample.map { $0.timestamp - minSample.timestamp }
    )
  }
}
