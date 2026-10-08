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
    // No transform. ARSCNView already presents the front camera the way a
    // mirror does, and draws its anchors in that same space. Flipping the view
    // again un-mirrored the image -- move right, the picture moved left --
    // which is the "inverted camera" people reported. Left alone, the image,
    // the face anchors and any overlay share one coordinate system.
    // Needs one check on a TrueDepth iPhone; the simulator cannot show it.
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

      // Not-ready is the state that needs attention, so it takes the accent;
      // ready goes quiet. Both sides previously resolved through `Palette` to
      // colours that are now identical, which would have left the guide ring
      // looking the same whether or not the person was positioned correctly.
      // The dash pattern carries the same distinction without relying on hue.
      Ellipse()
        .stroke(
          isReady ? DSPalette.textSecondary : DSPalette.accent,
          style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: isReady ? [] : [8, 8])
        )
        .frame(width: 210, height: 280)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
