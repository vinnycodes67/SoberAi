import ARKit
import SwiftUI

struct FaceCameraPreview: UIViewRepresentable {
  @ObservedObject var service: FaceTrackingService

  func makeUIView(context: Context) -> ARSCNView {
    let view = ARSCNView(frame: .zero)
    view.scene = SCNScene()
    view.automaticallyUpdatesLighting = true
    view.backgroundColor = .black
    view.contentMode = .scaleAspectFill
    view.transform = CGAffineTransform(scaleX: -1, y: 1)
    service.attach(to: view.session)
    return view
  }

  func updateUIView(_ uiView: ARSCNView, context: Context) {
    service.attach(to: uiView.session)
  }
}

struct FaceGuideOverlay: View {
  let isReady: Bool

  var body: some View {
    ZStack {
      Rectangle()
        .fill(.black.opacity(0.24))
        .mask {
          Rectangle()
            .overlay {
              Ellipse()
                .frame(width: 210, height: 280)
                .blendMode(.destinationOut)
            }
            .compositingGroup()
        }

      Ellipse()
        .stroke(
          isReady ? Palette.accent : Palette.warning,
          style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: isReady ? [] : [8, 8])
        )
        .frame(width: 210, height: 280)
        .shadow(color: (isReady ? Palette.accent : Palette.warning).opacity(0.42), radius: 16)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
