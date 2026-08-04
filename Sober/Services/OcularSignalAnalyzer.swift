import Foundation

struct OcularSignalAnalyzer: Sendable {
  func summarize(
    samples: [OcularSample],
    observedFrameCount: Int,
    liveQuality: CaptureQualitySnapshot,
    variant: OcularProtocolVariant = .full
  ) -> GazeCaptureSummary {
    guard samples.count >= 20,
      let first = samples.first,
      let last = samples.last,
      last.timestamp > first.timestamp
    else {
      var quality = liveQuality
      quality.sampleCount = samples.count
      quality.issues = deduplicated(quality.issues + [.insufficientSamples])
      return unusableSummary(quality: quality, sampleCount: samples.count, variant: variant)
    }

    let duration = last.timestamp - first.timestamp
    let frameRate = Double(samples.count - 1) / duration
    let dropoutRatio = observedFrameCount > 0
      ? max(1 - (Double(samples.count) / Double(observedFrameCount)), 0)
      : 1

    let fixation = samples.filter { $0.phase == .fixation }
    let horizontal = samples.filter { $0.phase == .horizontalPursuit }
    let vertical = samples.filter { $0.phase == .verticalPursuit }
    let saccades = samples.filter { $0.phase == .saccades }

    let fixationJitter = meanStepDistance(fixation)
    let horizontalError = correlationError(
      samples: horizontal,
      target: { $0.targetX },
      gaze: { ($0.leftGazeX + $0.rightGazeX) / 2 }
    )
    let verticalError = correlationError(
      samples: vertical,
      target: { $0.targetY },
      gaze: { ($0.leftGazeY + $0.rightGazeY) / 2 }
    )
    let saccadeError = max(
      correlationError(
        samples: saccades,
        target: { $0.targetX },
        gaze: { ($0.leftGazeX + $0.rightGazeX) / 2 }
      ),
      correlationError(
        samples: saccades,
        target: { $0.targetY },
        gaze: { ($0.leftGazeY + $0.rightGazeY) / 2 }
      )
    )
    let asymmetry = mean(samples.map {
      hypot($0.leftGazeX - $0.rightGazeX, $0.leftGazeY - $0.rightGazeY)
    })
    let headCompensation = meanHeadStepDistance(samples)
    // Blink rate is archived as an exploratory research feature. It does not
    // contribute to the prototype safety score.
    let blinks = countBlinkEvents(samples)
    let blinkRate = duration > 0 ? (Double(blinks) / duration) * 60 : 0

    let features = OcularSignalFeatures(
      fixationJitter: min(fixationJitter / 0.03, 1),
      horizontalPursuitError: horizontalError,
      verticalPursuitError: verticalError,
      saccadeError: saccadeError,
      leftRightAsymmetry: min(asymmetry / 0.08, 1),
      blinkRatePerMinute: blinkRate,
      headCompensation: min(headCompensation / 0.035, 1)
    )

    var quality = liveQuality
    quality.frameRate = frameRate
    quality.sampleCount = samples.count
    quality.dropoutRatio = dropoutRatio
    var issues = quality.issues.filter { ![.lowFrameRate, .interrupted, .insufficientSamples].contains($0) }
    if frameRate < 20 { issues.append(.lowFrameRate) }
    if dropoutRatio > 0.3 { issues.append(.interrupted) }
    quality.issues = deduplicated(issues)

    guard quality.isUsable else {
      return unusableSummary(
        quality: quality,
        sampleCount: samples.count,
        capturedDurationMilliseconds: duration * 1_000,
        features: features,
        variant: variant
      )
    }

    let smoothnessRisk: Double
    switch variant {
    case .full:
      let total = 0.22 + 0.25 + 0.18 + 0.2 + 0.15
      smoothnessRisk = min(max(
        (features.fixationJitter * 0.22 / total)
          + (horizontalError * 0.25 / total)
          + (verticalError * 0.18 / total)
          + (saccadeError * 0.2 / total)
          + (features.headCompensation * 0.15 / total),
        0
      ), 1)
    case .reducedMotion:
      let total = 0.22 + 0.2 + 0.15
      smoothnessRisk = min(max(
        (features.fixationJitter * 0.22 / total)
          + (saccadeError * 0.2 / total)
          + (features.headCompensation * 0.15 / total),
        0
      ), 1)
    }

    return GazeCaptureSummary(
      smoothnessRisk: smoothnessRisk,
      qualityScore: quality.score,
      sampleCount: samples.count,
      capturedDurationMilliseconds: duration * 1_000,
      quality: quality,
      features: features,
      protocolVariant: variant
    )
  }

  private func unusableSummary(
    quality: CaptureQualitySnapshot,
    sampleCount: Int,
    capturedDurationMilliseconds: Double = 0,
    features: OcularSignalFeatures = .unavailable,
    variant: OcularProtocolVariant = .full
  ) -> GazeCaptureSummary {
    GazeCaptureSummary(
      smoothnessRisk: 1,
      qualityScore: 0,
      sampleCount: sampleCount,
      capturedDurationMilliseconds: capturedDurationMilliseconds,
      quality: quality,
      features: features,
      protocolVariant: variant
    )
  }

  private func correlationError(
    samples: [OcularSample],
    target: (OcularSample) -> Double,
    gaze: (OcularSample) -> Double
  ) -> Double {
    guard samples.count >= 8 else { return 1 }
    let targetValues = samples.map(target)
    let gazeValues = samples.map(gaze)
    let targetMean = mean(targetValues)
    let gazeMean = mean(gazeValues)
    var numerator = 0.0
    var targetEnergy = 0.0
    var gazeEnergy = 0.0

    for index in samples.indices {
      let targetDelta = targetValues[index] - targetMean
      let gazeDelta = gazeValues[index] - gazeMean
      numerator += targetDelta * gazeDelta
      targetEnergy += targetDelta * targetDelta
      gazeEnergy += gazeDelta * gazeDelta
    }

    guard targetEnergy > 0.000_001, gazeEnergy > 0.000_001 else { return 1 }
    let correlation = numerator / sqrt(targetEnergy * gazeEnergy)
    return min(max(1 - abs(correlation), 0), 1)
  }

  private func meanStepDistance(_ samples: [OcularSample]) -> Double {
    guard samples.count > 1 else { return 1 }
    var distances: [Double] = []
    for index in 1..<samples.count {
      let currentX = (samples[index].leftGazeX + samples[index].rightGazeX) / 2
      let currentY = (samples[index].leftGazeY + samples[index].rightGazeY) / 2
      let priorX = (samples[index - 1].leftGazeX + samples[index - 1].rightGazeX) / 2
      let priorY = (samples[index - 1].leftGazeY + samples[index - 1].rightGazeY) / 2
      distances.append(hypot(currentX - priorX, currentY - priorY))
    }
    return mean(distances)
  }

  private func meanHeadStepDistance(_ samples: [OcularSample]) -> Double {
    guard samples.count > 1 else { return 1 }
    var distances: [Double] = []
    for index in 1..<samples.count {
      distances.append(sqrt(
        pow(samples[index].headX - samples[index - 1].headX, 2)
          + pow(samples[index].headY - samples[index - 1].headY, 2)
          + pow(samples[index].headZ - samples[index - 1].headZ, 2)
      ))
    }
    return mean(distances)
  }

  private func countBlinkEvents(_ samples: [OcularSample]) -> Int {
    var count = 0
    var wasClosed = false
    for sample in samples {
      let isClosed = max(sample.blinkLeft, sample.blinkRight) >= 0.65
      if isClosed && !wasClosed { count += 1 }
      wasClosed = isClosed
    }
    return count
  }

  private func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }

  private func deduplicated(_ issues: [CaptureQualityIssue]) -> [CaptureQualityIssue] {
    var seen: Set<CaptureQualityIssue> = []
    return issues.filter { seen.insert($0).inserted }
  }
}
