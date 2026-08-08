import AVFoundation
import Foundation

enum CameraPermissionState: String, Codable, Equatable, Sendable {
  case notDetermined
  case restricted
  case denied
  case authorized
}

/// System authorization is the source of truth. This protocol exists so the
/// app can reconcile permission changes deterministically without persisting a
/// second, potentially stale permission flag.
@MainActor
protocol PermissionStore: AnyObject {
  var cameraAuthorization: CameraPermissionState { get }
  func requestCameraAuthorization() async -> CameraPermissionState
}

@MainActor
final class SystemPermissionStore: PermissionStore {
  var cameraAuthorization: CameraPermissionState {
    Self.map(AVCaptureDevice.authorizationStatus(for: .video))
  }

  func requestCameraAuthorization() async -> CameraPermissionState {
    if cameraAuthorization == .notDetermined {
      _ = await AVCaptureDevice.requestAccess(for: .video)
    }
    return cameraAuthorization
  }

  static func map(_ status: AVAuthorizationStatus) -> CameraPermissionState {
    switch status {
    case .notDetermined: .notDetermined
    case .restricted: .restricted
    case .denied: .denied
    case .authorized: .authorized
    @unknown default: .denied
    }
  }
}
