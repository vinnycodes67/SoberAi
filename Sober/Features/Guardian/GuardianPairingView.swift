@preconcurrency import AVFoundation
import SwiftUI

/// Teen side: generates and displays a QR code inviting a parent to pair.
/// The invite is visible on screen the whole time — there is no way to
/// pair without this screen being open and shown to the other person.
struct GuardianPairingInviteView: View {
  @ObservedObject var pairing: GuardianPairingService
  let onPaired: (GuardianPairingInfo) -> Void

  @State private var refreshTask: Task<Void, Never>?

  var body: some View {
    FlowContainer(progress: nil) {
      ScreenHeader(
        eyebrow: "Guardian Mode",
        title: "Have your parent scan this.",
        detail:
          "This code pairs their phone with yours. They'll see your name, and you'll see theirs. Pairing is always visible to both of you."
      )

      switch pairing.status {
      case .working:
        ProgressView("Creating invite…")
          .frame(maxWidth: .infinity)
          .padding(.vertical, Space.xl)
      case .awaitingAcceptance(let url):
        qrCard(url: url)
      case .paired(let info):
        pairedCard(info: info)
      case .failed(let message):
        failedCard(message: message)
      case .notPaired:
        Color.clear.onAppear { Task { await pairing.createInvite() } }
      }
    }
    .task { await pairing.createInvite() }
    .onAppear { startPolling() }
    .onDisappear { refreshTask?.cancel() }
  }

  private func qrCard(url: URL) -> some View {
    VStack(spacing: Space.md) {
      if let image = pairing.qrImage(for: url) {
        Image(uiImage: image)
          .interpolation(.none)
          .resizable()
          .frame(width: 230, height: 230)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
      }
      Text("Waiting for your parent to scan…")
        .font(SoberType.subheadline)
        .foregroundStyle(Palette.textSecondary)
      ProgressView()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Space.sm)
  }

  private func pairedCard(info: GuardianPairingInfo) -> some View {
    SoberCard {
      HStack(spacing: Space.sm) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Palette.accent)
          .font(SoberType.title)
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text("Paired with \(info.participantName)")
            .font(SoberType.body)
          Text("They'll only see whether you completed a check, never a score.")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
  }

  private func failedCard(message: String) -> some View {
    VStack(spacing: Space.sm) {
      Text(message)
        .font(SoberType.subheadline)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
      Button("Try again") {
        Task { await pairing.createInvite() }
      }
      .buttonStyle(PrimaryActionButtonStyle())
    }
  }

  private func startPolling() {
    refreshTask = Task {
      while !Task.isCancelled {
        await pairing.refreshInviteStatus()
        if case .paired(let info) = pairing.status {
          onPaired(info)
          return
        }
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }
}

/// Parent side: scans the teen's QR code and accepts the pairing invite.
struct GuardianPairingScanView: View {
  @ObservedObject var pairing: GuardianPairingService
  let onPaired: (GuardianPairingInfo) -> Void

  @State private var scannedURL: URL?

  var body: some View {
    FlowContainer(progress: nil) {
      ScreenHeader(
        eyebrow: "Guardian Mode",
        title: "Scan your teen's code.",
        detail: "Ask them to open Guardian Mode on their phone and show you the QR code."
      )

      switch pairing.status {
      case .working:
        ProgressView("Pairing…")
          .frame(maxWidth: .infinity)
          .padding(.vertical, Space.xl)
      case .paired(let info):
        pairedCard(info: info)
      case .failed(let message):
        failedCard(message: message)
      default:
        QRScannerView { url in
          guard scannedURL == nil else { return }
          scannedURL = url
          Task {
            await pairing.acceptInvite(from: url)
            if case .paired(let info) = pairing.status {
              onPaired(info)
            }
          }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
      }
    }
  }

  private func pairedCard(info: GuardianPairingInfo) -> some View {
    SoberCard {
      HStack(spacing: Space.sm) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Palette.accent)
          .font(SoberType.title)
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text("Paired with \(info.participantName)")
            .font(SoberType.body)
          Text("You'll be notified if they haven't checked in before driving.")
            .font(SoberType.footnote)
            .foregroundStyle(Palette.textSecondary)
        }
      }
    }
  }

  private func failedCard(message: String) -> some View {
    VStack(spacing: Space.sm) {
      Text(message)
        .font(SoberType.subheadline)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
      Button("Scan again") {
        scannedURL = nil
      }
      .buttonStyle(PrimaryActionButtonStyle())
    }
  }
}

/// A minimal live QR scanner. Reports each decoded string exactly once per
/// distinct value scanned.
struct QRScannerView: UIViewControllerRepresentable {
  let onScan: (URL) -> Void

  func makeUIViewController(context: Context) -> QRScannerViewController {
    let controller = QRScannerViewController()
    controller.onScan = onScan
    return controller
  }

  func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onScan: ((URL) -> Void)?

  // AVCaptureSession isn't Sendable, but Apple's own guidance is to only
  // ever start/stop it off the main thread, so all access to it — from
  // `configureSession()` on the main actor and from the detached tasks
  // below — is already serialized onto AVCaptureSession's own internal
  // queue. `nonisolated(unsafe)` reflects that manually-verified safety.
  private nonisolated(unsafe) let session = AVCaptureSession()
  private var lastScannedString: String?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureSession()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !session.isRunning else { return }
    Task.detached { [session] in session.startRunning() }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    guard session.isRunning else { return }
    Task.detached { [session] in session.stopRunning() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  private var previewLayer: AVCaptureVideoPreviewLayer?

  private func configureSession() {
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else { return }
    session.addInput(input)

    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(layer)
    previewLayer = layer
  }

  // `setMetadataObjectsDelegate(self, queue: .main)` guarantees this always
  // fires on the main queue, but the delegate protocol itself isn't
  // main-actor-isolated — `assumeIsolated` bridges that runtime guarantee
  // into the type system rather than hopping with an async `Task`.
  // AVMetadataObject itself isn't Sendable, so the decoded string is
  // extracted here, in the nonisolated context, before crossing over.
  nonisolated func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard
      let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
      let value = code.stringValue
    else { return }

    MainActor.assumeIsolated {
      guard value != lastScannedString, let url = URL(string: value) else { return }
      lastScannedString = value
      onScan?(url)
    }
  }
}
