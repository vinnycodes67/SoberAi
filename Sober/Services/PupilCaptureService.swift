@preconcurrency import AVFoundation
import CoreImage
import CoreML
import Foundation
@preconcurrency import Vision

enum PupilCaptureStatus: Equatable {
  case idle
  case unavailable(String)
  case capturing
}

/// Wraps whatever CoreML model file is bundled for pupil/iris segmentation.
/// Until the trained model ships, this stays nil and pupillometry degrades
/// gracefully — the session still runs, every trial just reports no
/// reading — rather than crashing.
enum PupilSegmentationModel {
  static func makeRequest() -> VNCoreMLRequest? {
    guard
      let url = Bundle.main.url(forResource: "PupilSegmentation", withExtension: "mlmodelc"),
      let model = try? MLModel(contentsOf: url),
      let vnModel = try? VNCoreMLModel(for: model)
    else { return nil }
    let request = VNCoreMLRequest(model: vnModel)
    request.imageCropAndScaleOption = .scaleFill
    return request
  }
}

/// Fits an ellipse to a set of pixel coordinates via image moments
/// (centroid + eigen-decomposition of the covariance matrix). Pure math,
/// no third-party dependency — used to turn a segmentation mask's class
/// pixels into a pupil or iris diameter.
enum EllipseFit {
  struct Result {
    let centerX: Double
    let centerY: Double
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

    // Eigenvalues of the symmetric 2x2 covariance matrix [[cxx, cxy], [cxy, cyy]].
    let trace = cxx + cyy
    let determinant = cxx * cyy - cxy * cxy
    let discriminant = max(trace * trace / 4 - determinant, 0)
    let sqrtDiscriminant = discriminant.squareRoot()
    let lambda1 = trace / 2 + sqrtDiscriminant
    let lambda2 = max(trace / 2 - sqrtDiscriminant, 0)

    // For a uniformly filled ellipse, semi-axis length = 2 * sqrt(eigenvalue).
    let semiMajor = 2 * lambda1.squareRoot()
    let semiMinor = 2 * lambda2.squareRoot()

    return Result(
      centerX: meanX, centerY: meanY,
      majorAxis: semiMajor * 2, minorAxis: semiMinor * 2)
  }
}

/// Drives the front camera through a 3-trial pupillary light reflex (PLR)
/// protocol: per trial, the task view dark-adapts the screen, flashes it to
/// a target brightness, and this service turns the resulting frames into a
/// pupil-diameter-over-time trace, then a `PupilLightReflexTrial`.
///
/// Camera capture and Vision/CoreML inference run on a dedicated background
/// queue, never on the main actor — that work is too heavy to serialize
/// onto the UI thread. Only the lightweight per-frame result (a diameter in
/// mm, or a miss) hops back to the main actor to update state.
@MainActor
final class PupilCaptureService: NSObject, ObservableObject {
  @Published private(set) var status: PupilCaptureStatus = .idle

  // AVFoundation's own contract is that session control (start/stop) and
  // delegate callbacks are safe from a background queue as long as
  // configuration itself is bracketed by begin/commitConfiguration, which
  // happens once, synchronously, before the session starts running. The
  // type system can't see that invariant, hence the explicit unsafe
  // opt-out here rather than a false Sendable promise.
  private nonisolated(unsafe) let session = AVCaptureSession()
  private nonisolated(unsafe) let videoOutput = AVCaptureVideoDataOutput()
  private nonisolated(unsafe) let sequenceHandler = VNSequenceRequestHandler()
  private nonisolated(unsafe) let coreMLRequest: VNCoreMLRequest?
  private let processingQueue = DispatchQueue(label: "sober.pupil.processing")

  private var isCapturing = false
  private var flashOnsetTime: TimeInterval?
  private var samples: [(timestamp: TimeInterval, diameterMm: Double)] = []
  private var framesAttempted = 0
  private var framesWithReading = 0

  var isModelAvailable: Bool { coreMLRequest != nil }

  override init() {
    coreMLRequest = PupilSegmentationModel.makeRequest()
    super.init()
  }

  func start() {
    guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
      status = .unavailable("Camera access is off")
      return
    }
    status = .capturing
    let session = session
    let videoOutput = videoOutput
    let queue = processingQueue
    processingQueue.async { [weak self] in
      guard let self else { return }
      Self.configureIfNeeded(session: session, videoOutput: videoOutput, delegate: self, queue: queue)
      session.startRunning()
    }
  }

  func stop() {
    isCapturing = false
    let session = session
    processingQueue.async {
      session.stopRunning()
    }
  }

  func beginSession() {
    framesAttempted = 0
    framesWithReading = 0
  }

  /// Fraction of frames that produced a valid reading across the whole
  /// session — an honest capture-quality signal, not a fabricated one.
  func finishSession() -> Double {
    defer {
      framesAttempted = 0
      framesWithReading = 0
    }
    guard framesAttempted > 0 else { return 0 }
    return Double(framesWithReading) / Double(framesAttempted)
  }

  func beginTrial() {
    samples.removeAll()
    flashOnsetTime = nil
    isCapturing = true
  }

  func markFlashOnset() {
    flashOnsetTime = ProcessInfo.processInfo.systemUptime
  }

  func endTrial() -> PupilLightReflexTrial? {
    isCapturing = false
    defer { samples.removeAll() }
    return Self.deriveTrial(samples: samples, flashOnsetTime: flashOnsetTime)
  }

  private func recordSample(timestamp: TimeInterval, diameterMm: Double?) {
    guard isCapturing else { return }
    framesAttempted += 1
    if let diameterMm {
      framesWithReading += 1
      samples.append((timestamp, diameterMm))
    }
  }

  private nonisolated static func configureIfNeeded(
    session: AVCaptureSession,
    videoOutput: AVCaptureVideoDataOutput,
    delegate: AVCaptureVideoDataOutputSampleBufferDelegate,
    queue: DispatchQueue
  ) {
    guard session.inputs.isEmpty else { return }
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .high

    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else { return }
    session.addInput(input)

    if let format = bestHighFrameRateFormat(for: device),
      let range = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })
    {
      try? device.lockForConfiguration()
      device.activeFormat = format
      let duration = CMTime(value: 1, timescale: CMTimeScale(range.maxFrameRate))
      device.activeVideoMinFrameDuration = duration
      device.activeVideoMaxFrameDuration = duration
      device.unlockForConfiguration()
    }

    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.setSampleBufferDelegate(delegate, queue: queue)
    if session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
    }
  }

  private nonisolated static func bestHighFrameRateFormat(
    for device: AVCaptureDevice
  ) -> AVCaptureDevice.Format? {
    device.formats
      .filter { format in format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 } }
      .max { lhs, rhs in
        let lhsMax = lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let rhsMax = rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return lhsMax < rhsMax
      }
  }

  /// Turns a trial's raw (timestamp, diameter) samples into the PLR
  /// summary metrics. Internal (not private) so tests can exercise this
  /// pure function directly with synthetic data — no camera required.
  /// `nonisolated` because it's pure and callable from a plain synchronous
  /// test without hopping onto the main actor.
  nonisolated static func deriveTrial(
    samples: [(timestamp: TimeInterval, diameterMm: Double)],
    flashOnsetTime: TimeInterval?
  ) -> PupilLightReflexTrial? {
    guard let flashOnsetTime, samples.count >= 8 else { return nil }

    let preFlash = samples.filter { $0.timestamp < flashOnsetTime }
    let postFlash = samples.filter { $0.timestamp >= flashOnsetTime }.sorted { $0.timestamp < $1.timestamp }
    guard preFlash.count >= 4, postFlash.count >= 4 else { return nil }

    let baselineWindow = preFlash.filter { $0.timestamp >= flashOnsetTime - 2 }
    let baselineSet = baselineWindow.isEmpty ? preFlash : baselineWindow
    let baselineDiameter = baselineSet.map(\.diameterMm).reduce(0, +) / Double(baselineSet.count)

    guard let minSample = postFlash.min(by: { $0.diameterMm < $1.diameterMm }) else { return nil }
    let minDiameter = minSample.diameterMm

    // Onset = first post-flash sample at least 5% below baseline. A
    // disclosed, non-clinical threshold, not a claim of precision.
    let onsetThreshold = baselineDiameter * 0.95
    let onsetSample = postFlash.first { $0.diameterMm <= onsetThreshold }
    let latency = max((onsetSample?.timestamp ?? minSample.timestamp) - flashOnsetTime, 0)

    let constrictionPhase = postFlash.filter { $0.timestamp <= minSample.timestamp }
    var peakVelocity = 0.0
    if constrictionPhase.count >= 2 {
      for index in 1..<constrictionPhase.count {
        let previous = constrictionPhase[index - 1]
        let current = constrictionPhase[index]
        let dt = current.timestamp - previous.timestamp
        guard dt > 0 else { continue }
        peakVelocity = max(peakVelocity, (previous.diameterMm - current.diameterMm) / dt)
      }
    }

    let amplitude =
      baselineDiameter > 0
      ? min(max((baselineDiameter - minDiameter) / baselineDiameter, 0), 1) : 0

    // Recovery = first post-minimum sample back to 75% of the way from the
    // constriction minimum to baseline; nil if it never gets there within
    // the capture window rather than an estimated/extrapolated value.
    let recoveryTarget = minDiameter + 0.75 * (baselineDiameter - minDiameter)
    let recoverySample = postFlash.first {
      $0.timestamp >= minSample.timestamp && $0.diameterMm >= recoveryTarget
    }
    let recovery = recoverySample.map { $0.timestamp - minSample.timestamp }

    return PupilLightReflexTrial(
      baselineDiameterMm: baselineDiameter,
      minDiameterMm: minDiameter,
      latencySeconds: latency,
      peakConstrictionVelocityMmPerSecond: peakVelocity,
      amplitudePercent: amplitude,
      recoveryTo75PercentSeconds: recovery
    )
  }
}

extension PupilCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
    let diameterMm = Self.processFrame(
      pixelBuffer: pixelBuffer, sequenceHandler: sequenceHandler, coreMLRequest: coreMLRequest)

    Task { @MainActor [weak self] in
      self?.recordSample(timestamp: timestamp, diameterMm: diameterMm)
    }
  }
}

extension PupilCaptureService {
  /// The heavy per-frame work: landmarks -> eye crop -> CoreML segmentation
  /// -> ellipse fit -> iris-referenced diameter in mm. Takes everything it
  /// needs as parameters so it never touches actor-isolated state — this
  /// is what actually runs on the background processing queue.
  fileprivate nonisolated static func processFrame(
    pixelBuffer: CVPixelBuffer,
    sequenceHandler: VNSequenceRequestHandler,
    coreMLRequest: VNCoreMLRequest?
  ) -> Double? {
    guard let coreMLRequest else { return nil }

    let landmarksRequest = VNDetectFaceLandmarksRequest()
    guard
      (try? sequenceHandler.perform([landmarksRequest], on: pixelBuffer)) != nil,
      let face = landmarksRequest.results?.first,
      let landmarks = face.landmarks,
      let eyeRect = eyeCropRect(landmarks: landmarks, faceBoundingBox: face.boundingBox)
    else { return nil }

    let fullImage = CIImage(cvPixelBuffer: pixelBuffer)
    let extent = fullImage.extent
    let margin = 0.3
    let pixelRect = CGRect(
      x: eyeRect.origin.x * extent.width,
      y: eyeRect.origin.y * extent.height,
      width: eyeRect.width * extent.width,
      height: eyeRect.height * extent.height
    )
    .insetBy(dx: -eyeRect.width * extent.width * margin, dy: -eyeRect.height * extent.height * margin)
    .intersection(extent)
    guard !pixelRect.isEmpty else { return nil }

    let boosted = redChannelBoosted(fullImage.cropped(to: pixelRect))
    let handler = VNImageRequestHandler(ciImage: boosted, options: [:])
    guard
      (try? handler.perform([coreMLRequest])) != nil,
      let observation = coreMLRequest.results?.first as? VNCoreMLFeatureValueObservation,
      let multiArray = observation.featureValue.multiArrayValue
    else { return nil }

    let (pupilPoints, irisPoints) = classifyPixels(multiArray)
    guard
      let pupilEllipse = EllipseFit.fit(points: pupilPoints),
      let irisEllipse = EllipseFit.fit(points: irisPoints),
      irisEllipse.averageDiameter > 0
    else { return nil }

    // Iris-referenced scaling: dimensionless pixel ratio times a typical
    // adult iris diameter, so absolute camera distance/zoom cancels out.
    return (pupilEllipse.averageDiameter / irisEllipse.averageDiameter) * 11.7
  }

  fileprivate nonisolated static func eyeCropRect(
    landmarks: VNFaceLandmarks2D, faceBoundingBox: CGRect
  ) -> CGRect? {
    guard let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye else { return nil }
    let eye = leftEye.pointCount >= rightEye.pointCount ? leftEye : rightEye
    let points = eye.normalizedPoints
    guard !points.isEmpty else { return nil }

    let xs = points.map { Double($0.x) }
    let ys = points.map { Double($0.y) }
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
    else { return nil }

    // normalizedPoints are relative to the face bounding box; convert to
    // image-normalized coordinates.
    let relativeRect = CGRect(
      x: minX, y: minY, width: max(maxX - minX, 0.01), height: max(maxY - minY, 0.01))
    return CGRect(
      x: faceBoundingBox.origin.x + relativeRect.origin.x * faceBoundingBox.width,
      y: faceBoundingBox.origin.y + relativeRect.origin.y * faceBoundingBox.height,
      width: relativeRect.width * faceBoundingBox.width,
      height: relativeRect.height * faceBoundingBox.height
    )
  }

  /// Dark irises have poor pupil/iris contrast in balanced RGB; boosting
  /// the red channel's contribution improves the boundary the model sees.
  fileprivate nonisolated static func redChannelBoosted(_ image: CIImage) -> CIImage {
    guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(x: 1.6, y: 0, z: 0, w: 0), forKey: "inputRVector")
    filter.setValue(CIVector(x: 0, y: 0.8, z: 0, w: 0), forKey: "inputGVector")
    filter.setValue(CIVector(x: 0, y: 0, z: 0.8, w: 0), forKey: "inputBVector")
    filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
    return filter.outputImage ?? image
  }

  /// Handles both a [3, H, W] per-class probability/logit map (argmax per
  /// pixel) and a plain [H, W] integer label map, since the exact export
  /// convention depends on the training pipeline. Class order assumed:
  /// 0 = background, 1 = iris, 2 = pupil — the one spot to check first if
  /// integration with the real model produces empty ellipses.
  fileprivate nonisolated static func classifyPixels(_ multiArray: MLMultiArray) -> (
    pupil: [(x: Double, y: Double)], irisOrPupil: [(x: Double, y: Double)]
  ) {
    let shape = multiArray.shape.map(\.intValue)
    var pupilPoints: [(x: Double, y: Double)] = []
    var irisOrPupilPoints: [(x: Double, y: Double)] = []

    if shape.count == 3, shape[0] == 3 {
      let height = shape[1]
      let width = shape[2]
      for y in 0..<height {
        for x in 0..<width {
          var bestClass = 0
          var bestScore = -Double.infinity
          for classIndex in 0..<3 {
            let value = multiArray[[classIndex, y, x] as [NSNumber]].doubleValue
            if value > bestScore {
              bestScore = value
              bestClass = classIndex
            }
          }
          appendPoint(
            x: x, y: y, classIndex: bestClass, pupil: &pupilPoints, irisOrPupil: &irisOrPupilPoints)
        }
      }
    } else if shape.count == 2 {
      let height = shape[0]
      let width = shape[1]
      for y in 0..<height {
        for x in 0..<width {
          let label = multiArray[[y, x] as [NSNumber]].intValue
          appendPoint(
            x: x, y: y, classIndex: label, pupil: &pupilPoints, irisOrPupil: &irisOrPupilPoints)
        }
      }
    }

    return (pupilPoints, irisOrPupilPoints)
  }

  fileprivate nonisolated static func appendPoint(
    x: Int, y: Int, classIndex: Int,
    pupil: inout [(x: Double, y: Double)], irisOrPupil: inout [(x: Double, y: Double)]
  ) {
    guard classIndex == 1 || classIndex == 2 else { return }
    if classIndex == 2 {
      pupil.append((Double(x), Double(y)))
    }
    irisOrPupil.append((Double(x), Double(y)))
  }
}
