import AVFoundation
import Foundation
import LocalAuthentication

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

// MARK: - Privacy Lock

/// The result of asking iOS to verify the device owner. The app never receives,
/// stores, or implements a biometric or passcode credential itself.
enum PrivacyLockAuthenticationResult: Equatable, Sendable {
  case success
  case cancelled
  case unavailable
  case failed
}

/// A narrow LocalAuthentication boundary so lock behavior can be tested
/// without displaying system UI.
@MainActor
protocol PrivacyLockAuthenticating: AnyObject {
  var isAvailable: Bool { get }
  func authenticate(reason: String) async -> PrivacyLockAuthenticationResult
}

/// Uses `.deviceOwnerAuthentication`, not biometric-only authentication, so
/// Face ID or Touch ID can fall back to the person's device passcode through
/// iOS. Sober never creates a weaker custom PIN or recovery secret.
@MainActor
final class SystemPrivacyLockAuthenticator: PrivacyLockAuthenticating {
  var isAvailable: Bool {
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
  }

  func authenticate(reason: String) async -> PrivacyLockAuthenticationResult {
    let context = LAContext()
    context.localizedCancelTitle = "Cancel"

    var availabilityError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
      return .unavailable
    }

    do {
      return try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: reason
      ) ? .success : .failed
    } catch let error as LAError {
      return Self.map(error.code)
    } catch {
      return .failed
    }
  }

  static func map(_ code: LAError.Code) -> PrivacyLockAuthenticationResult {
    switch code {
    case .userCancel, .appCancel, .systemCancel:
      return .cancelled
    case .biometryNotAvailable, .passcodeNotSet:
      return .unavailable
    default:
      return .failed
    }
  }
}

/// The lock is armed only after the app has been away for the full interval.
/// A separate immediate shield hides protected content in the app switcher.
struct PrivacyLockPolicy: Equatable, Sendable {
  static let standard = PrivacyLockPolicy(inactivityInterval: 30)

  let inactivityInterval: TimeInterval

  func requiresAuthentication(inactiveSince: TimeInterval?, now: TimeInterval) -> Bool {
    guard let inactiveSince else { return false }
    return now - inactiveSince >= inactivityInterval
  }
}
