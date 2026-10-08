import Foundation

/// Computes `OcularDetailedMetrics` from the eye-task samples. Recording only:
/// nothing here feeds `smoothnessRisk`, `isUsable` or a baseline (HANDOFF 2.5).
///
/// Unlike the scored path, this does not give up on a whole capture because
/// part of it was poor. Each phase is measured from its valid samples when
/// there are enough of them, and says how much of the phase that was.
///
/// Every threshold below is an engineering choice made before any real
/// capture was looked at. They are named so they can be tuned against device
/// data, and `OcularDetailedMetrics.currentVersion` must be bumped when one is.
struct OcularDetailedAnalyzer: Sendable {
  // MARK: Units

  /// ARKit eye forward vectors are unit vectors in face space; for the few
  /// degrees a phone screen spans, their x and y components are the eye's
  /// rotation in radians to within 1%.
  static let degreesPerGazeUnit = 180 / Double.pi

  // MARK: Validity

  /// Lids this closed make the eye vector unreliable before the blink is full,
  /// so this sits below the 0.65 used to count blinks.
  static let eyesClosedThreshold = 0.5
  /// Samples this close to a closed-eye sample are lid transitions.
  static let blinkMarginSeconds = 0.05
  /// Head rotation speed above which eye-in-head angles stop tracking the
  /// target, degrees per second. Holding a phone still is well under 5.
  static let headSpeedLimit = 20.0
  /// An eye rotated further than about 37 degrees is not looking at a phone.
  static let implausibleGaze = 0.6
  /// Left and right eyes pointing this far apart, beyond their usual
  /// vergence offset, means one of the two vectors is wrong. Degrees.
  static let eyeDisagreementLimit = 10.0

  // MARK: Timing

  /// A gap longer than this between valid samples breaks a run: velocity is
  /// never taken across it. ARKit delivers about 60 Hz.
  static let maximumGapSeconds = 0.1
  /// Most time one sample can stand for when measuring coverage, so a
  /// dropout is not credited as observed.
  static let maximumSampleCredit = 0.05

  // MARK: Saccades (I-VT)

  /// Velocity threshold identification: an interval faster than this is part
  /// of a saccade. 30 deg/s is the usual I-VT setting (Salvucci & Goldberg
  /// 2000); pursuit on this protocol peaks near 8 deg/s. Velocity is the
  /// two-point difference of median-of-3 filtered gaze, which drops one-frame
  /// spikes without smearing a saccade across the 33 ms a central difference
  /// would at 60 Hz.
  static let saccadeVelocityThreshold = 30.0
  /// Movements smaller than this, in degrees, are treated as noise.
  static let minimumSaccadeAmplitude = 0.5

  // MARK: Phases

  /// Below this share of scheduled time covered by valid samples, a phase's
  /// measures are nil.
  static let minimumPhaseCoverage = 0.25
  static let minimumPhaseSamples = 15
  /// The first part of each pursuit phase is the eyes catching the target's
  /// starting point, not following it.
  static let pursuitSettlingSeconds = 0.4
  static let lagSearch: ClosedRange<Double> = -0.2...0.5
  static let lagStep = 1.0 / 30
  /// Gaze must follow the target at least this well before a lag is read.
  static let minimumTrackingCorrelation = 0.5
  /// A target jump the eyes did not move at least this far after is a jump
  /// with no response. Degrees; the protocol's smallest jump is several.
  static let minimumResponseAmplitude = 1.0
  /// Responses starting later than this after a jump are not counted.
  static let responseWindowSeconds = 0.7
  static let minimumJumpsForSummary = 3
  /// BCEA scale for 68% of points: -ln(1 - 0.682).
  static let bceaK = -log(1 - 0.682)

  func analyze(
    samples: [OcularSample],
    variant: OcularProtocolVariant,
    blinkCount: Int?,
    blinkRatePerMinute: Double?
  ) -> OcularDetailedMetrics? {
    guard variant != .noCamera else { return nil }
    var protocolSamples = samples.filter { $0.phase != .calibration && $0.timestamp.isFinite }
    if zip(protocolSamples, protocolSamples.dropFirst()).contains(where: { $0.timestamp > $1.timestamp }) {
      protocolSamples = protocolSamples.enumerated()
        .sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
        .map(\.element)
    }
    guard !protocolSamples.isEmpty else { return nil }

    let labels = Self.labels(for: protocolSamples)
    let track = Track(samples: protocolSamples, labels: labels)
    let phases = Self.phases(for: variant)

    let validTime = Self.validTime(samples: protocolSamples, labels: labels)
    var coverage = OcularPhaseCoverage()
    var coverageByPhase: [OcularPhase: Double] = [:]
    for phase in phases {
      let scheduled = Self.scheduledDuration(phase)
      let value = scheduled > 0 ? min(max((validTime.byPhase[phase] ?? 0) / scheduled, 0), 1) : 0
      coverageByPhase[phase] = value
      switch phase {
      case .fixation: coverage.fixation = value
      case .horizontalPursuit: coverage.horizontalPursuit = value
      case .verticalPursuit: coverage.verticalPursuit = value
      case .saccades: coverage.saccades = value
      case .calibration: break
      }
    }

    func enough(_ phase: OcularPhase) -> Double? {
      guard let value = coverageByPhase[phase], value >= Self.minimumPhaseCoverage,
        track.points.filter({ $0.phase == phase }).count >= Self.minimumPhaseSamples
      else { return nil }
      return value
    }

    let fixation = enough(.fixation).map { fixationMetrics(track: track, coverage: $0) }
    let saccadeResult = enough(.saccades).map {
      saccadeMetrics(track: track, samples: protocolSamples, coverage: $0)
    }
    let calibration = saccadeResult?.calibrationPoints ?? []
    var horizontal: OcularPursuitMetrics?
    var vertical: OcularPursuitMetrics?
    if phases.contains(.horizontalPursuit) {
      horizontal = enough(.horizontalPursuit).map {
        pursuitMetrics(
          phase: .horizontalPursuit, horizontal: true, track: track, samples: protocolSamples,
          scale: Self.calibrationSlope(calibration, horizontal: true, track: track), coverage: $0)
      }
    }
    if phases.contains(.verticalPursuit) {
      vertical = enough(.verticalPursuit).map {
        pursuitMetrics(
          phase: .verticalPursuit, horizontal: false, track: track, samples: protocolSamples,
          scale: Self.calibrationSlope(calibration, horizontal: false, track: track), coverage: $0)
      }
    }

    let validSeconds = validTime.total
    let transitions = track.points.isEmpty ? nil : track.events.count
    let transitionRate = validSeconds >= 1
      ? transitions.flatMap { Self.finite(Double($0) / validSeconds * 60) }
      : nil

    return OcularDetailedMetrics(
      version: OcularDetailedMetrics.currentVersion,
      validity: Self.fractions(labels: labels, samples: protocolSamples),
      coverage: coverage,
      fixation: fixation,
      horizontalPursuit: horizontal,
      verticalPursuit: vertical,
      saccades: saccadeResult?.metrics,
      gazeTransitionCount: transitions,
      gazeTransitionsPerMinute: transitionRate,
      binocular: binocularMetrics(samples: protocolSamples, labels: labels),
      blinkCount: blinkCount,
      blinkRatePerMinute: blinkRatePerMinute.flatMap(Self.finite)
    )
  }

  // MARK: - Validity labels

  /// One label per sample, in priority order missing, eyesClosed, headMoved,
  /// lowConfidence, valid. `samples` must be sorted by timestamp.
  static func labels(for samples: [OcularSample]) -> [OcularSampleValidity] {
    let count = samples.count
    var labels = [OcularSampleValidity](repeating: .valid, count: count)
    guard count > 0 else { return labels }

    func gazeFinite(_ s: OcularSample) -> Bool {
      s.leftGazeX.isFinite && s.leftGazeY.isFinite && s.rightGazeX.isFinite && s.rightGazeY.isFinite
        && !(s.leftGazeX == 0 && s.leftGazeY == 0 && s.rightGazeX == 0 && s.rightGazeY == 0)
    }
    func headFinite(_ s: OcularSample) -> Bool {
      s.headX.isFinite && s.headY.isFinite && s.headZ.isFinite
    }

    // The eyes' usual vergence offset, so only disagreement beyond it counts.
    let finiteSamples = samples.filter(gazeFinite)
    let offsetX = median(finiteSamples.map { $0.leftGazeX - $0.rightGazeX }) ?? 0
    let offsetY = median(finiteSamples.map { $0.leftGazeY - $0.rightGazeY }) ?? 0

    func lidClosed(_ value: Double?) -> Bool {
      guard let value, value.isFinite else { return false }
      return value >= eyesClosedThreshold
    }

    var closedTimes: [Double] = []
    for index in 0..<count {
      let sample = samples[index]
      guard gazeFinite(sample) else {
        labels[index] = .missing
        continue
      }
      if lidClosed(sample.blinkLeft) || lidClosed(sample.blinkRight) {
        labels[index] = .eyesClosed
        closedTimes.append(sample.timestamp)
        continue
      }
      let before = max(index - 1, 0)
      let after = min(index + 1, count - 1)
      if before != after, headFinite(samples[before]), headFinite(samples[after]) {
        let dt = samples[after].timestamp - samples[before].timestamp
        if dt > 0 {
          let a = samples[before]
          let b = samples[after]
          let chord = sqrt(
            (b.headX - a.headX) * (b.headX - a.headX)
              + (b.headY - a.headY) * (b.headY - a.headY)
              + (b.headZ - a.headZ) * (b.headZ - a.headZ))
          if chord / dt * degreesPerGazeUnit > headSpeedLimit {
            labels[index] = .headMoved
            continue
          }
        }
      }
      let implausible = max(
        abs(sample.leftGazeX), abs(sample.leftGazeY), abs(sample.rightGazeX), abs(sample.rightGazeY)
      ) > implausibleGaze
      let disagreement = hypot(
        sample.leftGazeX - sample.rightGazeX - offsetX,
        sample.leftGazeY - sample.rightGazeY - offsetY) * degreesPerGazeUnit
      if implausible || disagreement > eyeDisagreementLimit {
        labels[index] = .lowConfidence
      }
    }

    // Lid transitions on either side of a closure.
    if !closedTimes.isEmpty {
      var pointer = 0
      for index in 0..<count where labels[index] == .valid {
        let time = samples[index].timestamp
        while pointer + 1 < closedTimes.count, closedTimes[pointer + 1] <= time { pointer += 1 }
        let nearest = min(
          abs(closedTimes[pointer] - time),
          pointer + 1 < closedTimes.count ? abs(closedTimes[pointer + 1] - time) : .infinity)
        if nearest <= blinkMarginSeconds { labels[index] = .lowConfidence }
      }
    }
    return labels
  }

  // MARK: - Track of valid samples

  struct Point {
    let t: Double
    let phase: OcularPhase
    let x: Double
    let y: Double
    let leftX: Double
    let leftY: Double
    let rightX: Double
    let rightY: Double
    let segment: Int
    var fx = 0.0
    var fy = 0.0
  }

  struct Event {
    /// Interval indices: interval k runs from point k to k + 1.
    let first: Int
    let last: Int
    /// Midpoint of the first above-threshold interval, within half a frame
    /// of when the eye left.
    let onset: Double
    let fromX: Double
    let fromY: Double
    let toX: Double
    let toY: Double
    let amplitude: Double
    /// Phase of the first sample after the eye left. A jump made because the
    /// target moved into a new phase belongs to that phase.
    let phase: OcularPhase
  }

  /// Valid samples in time order with filtered positions, interval
  /// velocities and the saccades found in them.
  struct Track {
    var points: [Point] = []
    /// Speed of interval k (point k to k + 1) in deg/s; nil across a gap.
    var intervalSpeed: [Double?] = []
    var intervalVX: [Double] = []
    var intervalVY: [Double] = []
    var events: [Event] = []
    /// Interval k is inside or within two intervals of a saccade.
    var nearSaccade: [Bool] = []

    init(samples: [OcularSample], labels: [OcularSampleValidity]) {
      var segment = 0
      for (sample, label) in zip(samples, labels) where label == .valid {
        if let last = points.last {
          let dt = sample.timestamp - last.t
          if dt <= 0 { continue }
          if dt > OcularDetailedAnalyzer.maximumGapSeconds { segment += 1 }
        }
        points.append(Point(
          t: sample.timestamp, phase: sample.phase,
          x: (sample.leftGazeX + sample.rightGazeX) / 2,
          y: (sample.leftGazeY + sample.rightGazeY) / 2,
          leftX: sample.leftGazeX, leftY: sample.leftGazeY,
          rightX: sample.rightGazeX, rightY: sample.rightGazeY,
          segment: segment))
      }
      let count = points.count
      guard count > 0 else { return }

      // Median of 3 within a segment: removes a one-frame spike, keeps a step.
      for index in 0..<count {
        let p = points[index]
        if index > 0, index < count - 1,
          points[index - 1].segment == p.segment, points[index + 1].segment == p.segment
        {
          points[index].fx = OcularDetailedAnalyzer.median3(points[index - 1].x, p.x, points[index + 1].x)
          points[index].fy = OcularDetailedAnalyzer.median3(points[index - 1].y, p.y, points[index + 1].y)
        } else {
          points[index].fx = p.x
          points[index].fy = p.y
        }
      }

      let intervals = max(count - 1, 0)
      intervalSpeed = Array(repeating: nil, count: intervals)
      intervalVX = Array(repeating: 0, count: intervals)
      intervalVY = Array(repeating: 0, count: intervals)
      nearSaccade = Array(repeating: false, count: intervals)
      for k in 0..<intervals where points[k].segment == points[k + 1].segment {
        let dt = points[k + 1].t - points[k].t
        let vx = (points[k + 1].fx - points[k].fx) / dt
        let vy = (points[k + 1].fy - points[k].fy) / dt
        intervalVX[k] = vx
        intervalVY[k] = vy
        intervalSpeed[k] = hypot(vx, vy) * OcularDetailedAnalyzer.degreesPerGazeUnit
      }

      var k = 0
      while k < intervals {
        guard let speed = intervalSpeed[k], speed >= OcularDetailedAnalyzer.saccadeVelocityThreshold
        else {
          k += 1
          continue
        }
        var last = k
        while last + 1 < intervals, let next = intervalSpeed[last + 1],
          next >= OcularDetailedAnalyzer.saccadeVelocityThreshold
        {
          last += 1
        }
        let from = points[k]
        let to = points[last + 1]
        let amplitude = hypot(to.fx - from.fx, to.fy - from.fy) * OcularDetailedAnalyzer.degreesPerGazeUnit
        if amplitude >= OcularDetailedAnalyzer.minimumSaccadeAmplitude {
          events.append(Event(
            first: k, last: last, onset: (from.t + points[k + 1].t) / 2,
            fromX: from.fx, fromY: from.fy, toX: to.fx, toY: to.fy,
            amplitude: amplitude, phase: points[k + 1].phase))
          for flagged in max(k - 2, 0)...min(last + 2, intervals - 1) { nearSaccade[flagged] = true }
        }
        k = last + 1
      }
    }
  }

  // MARK: - Fixation

  private func fixationMetrics(track: Track, coverage: Double) -> OcularFixationMetrics {
    let indices = track.points.indices.filter { track.points[$0].phase == .fixation }
    let xs = indices.map { track.points[$0].x * Self.degreesPerGazeUnit }
    let ys = indices.map { track.points[$0].y * Self.degreesPerGazeUnit }
    var rms: Double?
    var bcea: Double?
    if xs.count >= 2 {
      let mx = Self.mean(xs)
      let my = Self.mean(ys)
      var sxx = 0.0, syy = 0.0, sxy = 0.0
      for i in xs.indices {
        sxx += (xs[i] - mx) * (xs[i] - mx)
        syy += (ys[i] - my) * (ys[i] - my)
        sxy += (xs[i] - mx) * (ys[i] - my)
      }
      let n = Double(xs.count)
      rms = Self.finite(sqrt((sxx + syy) / n))
      let sdx = sqrt(sxx / (n - 1))
      let sdy = sqrt(syy / (n - 1))
      let rho = sdx > 0 && sdy > 0 ? min(max(sxy / (n - 1) / (sdx * sdy), -1), 1) : 0
      bcea = Self.finite(2 * Double.pi * Self.bceaK * sdx * sdy * sqrt(1 - rho * rho))
    }

    // Longest run of fixation points joined by non-saccadic intervals.
    var longest: Double?
    var runStart: Double?
    var previous: Int?
    for index in indices {
      if let prior = previous, prior + 1 == index, let speed = track.intervalSpeed[prior],
        speed < Self.saccadeVelocityThreshold, let start = runStart
      {
        let length = track.points[index].t - start
        longest = max(longest ?? 0, length)
      } else {
        runStart = track.points[index].t
      }
      previous = index
    }

    return OcularFixationMetrics(
      coverage: coverage,
      dispersionRMSDegrees: rms,
      bceaSquareDegrees: bcea,
      longestStableMilliseconds: longest.flatMap { Self.finite($0 * 1_000) },
      intrusiveSaccadeCount: track.events.filter { $0.phase == .fixation }.count
    )
  }

  // MARK: - Pursuit

  private func pursuitMetrics(
    phase: OcularPhase,
    horizontal: Bool,
    track: Track,
    samples: [OcularSample],
    scale: Double?,
    coverage: Double
  ) -> OcularPursuitMetrics {
    let phaseSamples = samples.filter { $0.phase == phase }
    let targetTimes = phaseSamples.map(\.timestamp)
    let targetValues = phaseSamples.map { horizontal ? $0.targetX : $0.targetY }
    let start = (targetTimes.first ?? 0) + Self.pursuitSettlingSeconds
    let indices = track.points.indices.filter {
      track.points[$0].phase == phase && track.points[$0].t >= start
    }
    let catchUps = track.events.filter { $0.phase == phase && $0.onset >= start }.count

    guard indices.count >= Self.minimumPhaseSamples, targetTimes.count >= 2,
      (targetValues.max() ?? 0) - (targetValues.min() ?? 0) > 0.05
    else {
      return OcularPursuitMetrics(coverage: coverage, gain: nil, lagMilliseconds: nil, catchUpSaccadeCount: catchUps)
    }

    let gazeTimes = indices.map { track.points[$0].t }
    let gazeAxis = indices.map { horizontal ? track.points[$0].fx : track.points[$0].fy }

    // Cross-correlation over the lag range, refined by a parabola through the
    // best step and its neighbours.
    func correlation(at lag: Double) -> Double? {
      var n = 0.0, sg = 0.0, st = 0.0, sgg = 0.0, stt = 0.0, sgt = 0.0
      var cursor = 0
      for index in gazeTimes.indices {
        guard let target = Self.interpolate(targetTimes, targetValues, at: gazeTimes[index] - lag, cursor: &cursor)
        else { continue }
        let gaze = gazeAxis[index]
        n += 1
        sg += gaze
        st += target
        sgg += gaze * gaze
        stt += target * target
        sgt += gaze * target
      }
      guard n >= Double(Self.minimumPhaseSamples) else { return nil }
      let covariance = sgt - sg * st / n
      let gazeEnergy = sgg - sg * sg / n
      let targetEnergy = stt - st * st / n
      guard gazeEnergy > 1e-12, targetEnergy > 1e-12 else { return nil }
      return Self.finite(min(abs(covariance) / sqrt(gazeEnergy * targetEnergy), 1))
    }

    let steps = Int(((Self.lagSearch.upperBound - Self.lagSearch.lowerBound) / Self.lagStep).rounded())
    let lags = (0...steps).map { Self.lagSearch.lowerBound + Double($0) * Self.lagStep }
    var cache: [Int: Double?] = [:]
    func score(_ index: Int) -> Double? {
      if let cached = cache[index] { return cached }
      let value = correlation(at: lags[index])
      cache[index] = value
      return value
    }
    // Every third step first: against targets with 3 and 4 s periods, |r| has
    // one smooth peak in this range, so the best coarse step brackets it.
    var lag: Double?
    let coarse = stride(from: 0, to: lags.count, by: 3).compactMap { index in score(index).map { (index, $0) } }
    if let coarseBest = coarse.max(by: { $0.1 < $1.1 })?.0 {
      let near = max(coarseBest - 2, 0)...min(coarseBest + 2, lags.count - 1)
      let best = near.compactMap { index in score(index).map { (index, $0) } }.max(by: { $0.1 < $1.1 })
      if let (best, peak) = best, peak >= Self.minimumTrackingCorrelation,
        best > 0, best < lags.count - 1,
        let left = score(best - 1), let right = score(best + 1)
      {
        let curvature = left - 2 * peak + right
        let offset = curvature < 0 ? min(max(0.5 * (left - right) / curvature, -0.5), 0.5) : 0
        lag = lags[best] + offset * Self.lagStep
      }
    }

    // Gain: eye velocity in screen units over target velocity at the lag,
    // saccade intervals removed. Needs the saccade-phase scale.
    var gain: Double?
    if let scale {
      let shift = lag ?? 0
      var numerator = 0.0
      var energy = 0.0
      var used = 0
      var lower = 0
      var upper = 0
      let h = 0.02
      for k in 0..<track.intervalSpeed.count {
        guard track.intervalSpeed[k] != nil, !track.nearSaccade[k],
          track.points[k].phase == phase, track.points[k].t >= start
        else { continue }
        let mid = (track.points[k].t + track.points[k + 1].t) / 2 - shift
        guard let before = Self.interpolate(targetTimes, targetValues, at: mid - h, cursor: &lower),
          let after = Self.interpolate(targetTimes, targetValues, at: mid + h, cursor: &upper)
        else { continue }
        let targetVelocity = (after - before) / (2 * h)
        let eyeVelocity = (horizontal ? track.intervalVX[k] : track.intervalVY[k]) / scale
        numerator += eyeVelocity * targetVelocity
        energy += targetVelocity * targetVelocity
        used += 1
      }
      if used >= Self.minimumPhaseSamples, energy > 1e-6 {
        gain = Self.finite(numerator / energy)
      }
    }

    return OcularPursuitMetrics(
      coverage: coverage,
      gain: gain,
      lagMilliseconds: lag.flatMap { Self.finite($0 * 1_000) },
      catchUpSaccadeCount: catchUps
    )
  }

  // MARK: - Saccades

  struct CalibrationPoint {
    let targetX: Double
    let targetY: Double
    let x: Double
    let y: Double
  }

  private struct SaccadeResult {
    let metrics: OcularSaccadeMetrics
    let calibrationPoints: [CalibrationPoint]
  }

  private func saccadeMetrics(track: Track, samples: [OcularSample], coverage: Double) -> SaccadeResult {
    // A jump is the first sample showing a new target. It is only timed when
    // the sample before it is recent, so a dropout cannot hide the real jump.
    var jumps: [(time: Double, x: Double, y: Double, timed: Bool)] = []
    for index in samples.indices where samples[index].phase == .saccades && index > 0 {
      let prior = samples[index - 1]
      let sample = samples[index]
      if abs(sample.targetX - prior.targetX) > 0.02 || abs(sample.targetY - prior.targetY) > 0.02 {
        jumps.append((
          sample.timestamp, sample.targetX, sample.targetY,
          sample.timestamp - prior.timestamp <= Self.maximumGapSeconds))
      }
    }
    let phaseEnd = samples.last(where: { $0.phase == .saccades })?.timestamp ?? 0
    let frame = Self.median(Self.positiveIntervals(samples)) ?? (1.0 / 60)

    func positions(from start: Double, to end: Double) -> ArraySlice<Point> {
      let points = track.points
      var low = 0
      var high = points.count
      while low < high {
        let middle = (low + high) / 2
        if points[middle].t < start { low = middle + 1 } else { high = middle }
      }
      var last = low
      while last < points.count, points[last].t < end { last += 1 }
      return points[low..<last]
    }

    var measured: [OcularSaccadeJump] = []
    var calibration: [CalibrationPoint] = []
    for (index, jump) in jumps.enumerated() where jump.timed {
      let end = min(index + 1 < jumps.count ? jumps[index + 1].time : phaseEnd + frame, jump.time + 1.2)
      guard end - jump.time >= 0.5 else { continue }
      let pre = positions(from: jump.time - 0.15, to: jump.time + 0.05)
      let settled = positions(from: end - 0.3 * (end - jump.time), to: end)
      let response = positions(from: jump.time, to: jump.time + 0.5)
      guard pre.count >= 3, settled.count >= 3,
        Double(response.count) >= 0.5 * (0.5 / frame),
        let preX = Self.median(pre.map(\.fx)), let preY = Self.median(pre.map(\.fy)),
        let endX = Self.median(settled.map(\.fx)), let endY = Self.median(settled.map(\.fy))
      else { continue }

      let dx = endX - preX
      let dy = endY - preY
      let distance = hypot(dx, dy)
      guard distance * Self.degreesPerGazeUnit >= Self.minimumResponseAmplitude else {
        measured.append(OcularSaccadeJump(
          responded: false, latencyMilliseconds: nil, primaryGain: nil, landingError: nil,
          correctiveSaccadeCount: 0))
        continue
      }

      let windowEnd = min(jump.time + Self.responseWindowSeconds, end)
      let primaryIndex = track.events.firstIndex { event in
        guard event.onset >= jump.time, event.onset < windowEnd else { return false }
        let along = ((event.toX - event.fromX) * dx + (event.toY - event.fromY) * dy) / distance
        return along >= 0.3 * distance
      }
      guard let primaryIndex else {
        measured.append(OcularSaccadeJump(
          responded: false, latencyMilliseconds: nil, primaryGain: nil, landingError: nil,
          correctiveSaccadeCount: 0))
        continue
      }
      let primary = track.events[primaryIndex]
      let corrective = track.events[(primaryIndex + 1)...].filter { $0.onset < end }.count
      let gain = ((primary.toX - preX) * dx + (primary.toY - preY) * dy) / (distance * distance)
      let landing = hypot(primary.toX - endX, primary.toY - endY) / distance
      measured.append(OcularSaccadeJump(
        responded: true,
        latencyMilliseconds: Self.finite(max(primary.onset - jump.time, 0) * 1_000),
        primaryGain: Self.finite(gain),
        landingError: Self.finite(landing),
        correctiveSaccadeCount: corrective))
      calibration.append(CalibrationPoint(targetX: jump.x, targetY: jump.y, x: endX, y: endY))
    }

    let responded = measured.filter(\.responded)
    let enoughJumps = measured.count >= Self.minimumJumpsForSummary
    let enoughResponses = responded.count >= Self.minimumJumpsForSummary
    let metrics = OcularSaccadeMetrics(
      coverage: coverage,
      jumpCount: jumps.count,
      analysedJumpCount: measured.count,
      respondedFraction: enoughJumps ? Double(responded.count) / Double(measured.count) : nil,
      medianLatencyMilliseconds: enoughResponses ? Self.median(responded.compactMap(\.latencyMilliseconds)) : nil,
      medianPrimaryGain: enoughResponses ? Self.median(responded.compactMap(\.primaryGain)) : nil,
      medianLandingError: enoughResponses ? Self.median(responded.compactMap(\.landingError)) : nil,
      correctiveSaccadeCount: measured.reduce(0) { $0 + $1.correctiveSaccadeCount },
      jumps: measured
    )
    return SaccadeResult(metrics: metrics, calibrationPoints: calibration)
  }

  /// Gaze units per screen unit along one axis, from where the eyes settled
  /// on each saccade target plus the fixation centre. The sign is part of the
  /// fit, so it does not matter which way ARKit's axes face the screen. Nil
  /// unless the fit is tight over a real spread of targets.
  static func calibrationSlope(_ points: [CalibrationPoint], horizontal: Bool, track: Track) -> Double? {
    var targets = points.map { horizontal ? $0.targetX : $0.targetY }
    var gaze = points.map { horizontal ? $0.x : $0.y }
    let centre = track.points.filter { $0.phase == .fixation }.map { horizontal ? $0.fx : $0.fy }
    if centre.count >= minimumPhaseSamples, let value = median(centre) {
      targets.append(0.5)
      gaze.append(value)
    }
    guard targets.count >= 3, (targets.max() ?? 0) - (targets.min() ?? 0) >= 0.3,
      let r = pearson(targets, gaze), abs(r) >= 0.7
    else { return nil }
    let mt = mean(targets)
    let mg = mean(gaze)
    var numerator = 0.0
    var denominator = 0.0
    for i in targets.indices {
      numerator += (targets[i] - mt) * (gaze[i] - mg)
      denominator += (targets[i] - mt) * (targets[i] - mt)
    }
    guard denominator > 0 else { return nil }
    let slope = numerator / denominator
    // Under a degree across the whole screen is no scale at all.
    guard abs(slope) * degreesPerGazeUnit >= 1, slope.isFinite else { return nil }
    return slope
  }

  // MARK: - Binocular

  private func binocularMetrics(
    samples: [OcularSample], labels: [OcularSampleValidity]
  ) -> OcularBinocularMetrics? {
    // One pass of running sums: this runs on every capture.
    var n = 0.0
    var sums = [Double](repeating: 0, count: 14)
    for (sample, label) in zip(samples, labels) where label == .valid {
      let (lx, ly, rx, ry) = (sample.leftGazeX, sample.leftGazeY, sample.rightGazeX, sample.rightGazeY)
      n += 1
      sums[0] += lx; sums[1] += rx; sums[2] += lx * lx; sums[3] += rx * rx; sums[4] += lx * rx
      sums[5] += ly; sums[6] += ry; sums[7] += ly * ly; sums[8] += ry * ry; sums[9] += ly * ry
      let dx = lx - rx
      let dy = ly - ry
      sums[10] += dx; sums[11] += dy; sums[12] += dx * dx; sums[13] += dy * dy
    }
    guard n >= Double(Self.minimumPhaseSamples) else { return nil }
    // Each eye must move at least half a degree (standard deviation) on an
    // axis before the two are correlated on it.
    let minimumEnergy = pow(0.5 / Self.degreesPerGazeUnit, 2) * (n - 1)
    var correlations: [Double] = []
    for offset in [0, 5] {
      let left = sums[offset + 2] - sums[offset] * sums[offset] / n
      let right = sums[offset + 3] - sums[offset + 1] * sums[offset + 1] / n
      let cross = sums[offset + 4] - sums[offset] * sums[offset + 1] / n
      guard left >= minimumEnergy, right >= minimumEnergy,
        let r = Self.finite(cross / sqrt(left * right))
      else { continue }
      correlations.append(min(max(r, -1), 1))
    }
    let spread = (sums[12] - sums[10] * sums[10] / n) + (sums[13] - sums[11] * sums[11] / n)
    return OcularBinocularMetrics(
      leftRightCorrelation: correlations.isEmpty ? nil : Self.finite(Self.mean(correlations)),
      disagreementRMSDegrees: Self.finite(sqrt(max(spread, 0) / n) * Self.degreesPerGazeUnit)
    )
  }

  // MARK: - Coverage and fractions

  static func phases(for variant: OcularProtocolVariant) -> [OcularPhase] {
    switch variant {
    case .full: [.fixation, .horizontalPursuit, .verticalPursuit, .saccades]
    case .reducedMotion: [.fixation, .saccades]
    case .noCamera: []
    }
  }

  static func scheduledDuration(_ phase: OcularPhase) -> Double {
    switch phase {
    case .fixation: OcularProtocolSchedule.fixationDuration
    case .horizontalPursuit: OcularProtocolSchedule.horizontalDuration
    case .verticalPursuit: OcularProtocolSchedule.verticalDuration
    case .saccades: OcularProtocolSchedule.saccadeDuration
    case .calibration: 0
    }
  }

  /// Valid time per phase and in total. Each valid sample stands for the
  /// time to the next sample, capped so a dropout is never credited as
  /// observed; the last sample of a phase stands for one typical frame.
  static func validTime(
    samples: [OcularSample], labels: [OcularSampleValidity]
  ) -> (byPhase: [OcularPhase: Double], total: Double) {
    let frame = min(median(positiveIntervals(samples)) ?? maximumSampleCredit, maximumSampleCredit)
    var byPhase: [OcularPhase: Double] = [:]
    var total = 0.0
    for index in samples.indices where labels[index] == .valid {
      var step = frame
      if index + 1 < samples.count, samples[index + 1].phase == samples[index].phase {
        step = samples[index + 1].timestamp - samples[index].timestamp
      }
      let credit = min(max(step, 0), maximumSampleCredit)
      byPhase[samples[index].phase, default: 0] += credit
      total += credit
    }
    return (byPhase, total)
  }

  private static func fractions(labels: [OcularSampleValidity], samples: [OcularSample]) -> OcularValidityFractions {
    let n = Double(labels.count)
    func share(_ label: OcularSampleValidity) -> Double {
      n > 0 ? Double(labels.filter { $0 == label }.count) / n : 0
    }
    let unknown = samples.filter { $0.blinkLeft == nil && $0.blinkRight == nil }.count
    return OcularValidityFractions(
      sampleCount: labels.count,
      valid: share(.valid),
      lowConfidence: share(.lowConfidence),
      eyesClosed: share(.eyesClosed),
      headMoved: share(.headMoved),
      missing: share(.missing),
      eyeStateUnknown: n > 0 ? Double(unknown) / n : 0
    )
  }

  // MARK: - Arithmetic

  static func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }

  static func median3(_ a: Double, _ b: Double, _ c: Double) -> Double {
    max(min(a, b), min(max(a, b), c))
  }

  static func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
  }

  static func median(_ values: [Double]) -> Double? {
    let sorted = values.filter(\.isFinite).sorted()
    guard !sorted.isEmpty else { return nil }
    let middle = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
  }

  static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
    guard a.count == b.count, a.count >= 3 else { return nil }
    let ma = mean(a)
    let mb = mean(b)
    var ab = 0.0, aa = 0.0, bb = 0.0
    for i in a.indices {
      ab += (a[i] - ma) * (b[i] - mb)
      aa += (a[i] - ma) * (a[i] - ma)
      bb += (b[i] - mb) * (b[i] - mb)
    }
    guard aa > 1e-12, bb > 1e-12 else { return nil }
    return finite(min(max(ab / sqrt(aa * bb), -1), 1))
  }

  static func positiveIntervals(_ samples: [OcularSample]) -> [Double] {
    guard samples.count > 1 else { return [] }
    return (1..<samples.count).map { samples[$0].timestamp - samples[$0 - 1].timestamp }.filter { $0 > 0 }
  }

  /// Linear interpolation in ascending `times`. `cursor` makes a sweep with
  /// rising `time` linear overall. Nil outside the sampled range.
  static func interpolate(_ times: [Double], _ values: [Double], at time: Double, cursor: inout Int) -> Double? {
    guard let first = times.first, let last = times.last, time >= first, time <= last else { return nil }
    guard times.count >= 2 else { return values[0] }
    cursor = min(max(cursor, 0), times.count - 2)
    if times[cursor] > time { cursor = 0 }
    while cursor + 1 <= times.count - 2, times[cursor + 1] <= time { cursor += 1 }
    let span = times[cursor + 1] - times[cursor]
    guard span > 0 else { return values[cursor] }
    let fraction = (time - times[cursor]) / span
    return values[cursor] + (values[cursor + 1] - values[cursor]) * fraction
  }
}
