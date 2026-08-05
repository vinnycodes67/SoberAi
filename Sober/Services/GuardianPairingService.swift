import CloudKit
import Contacts
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

/// Mutual, visible pairing between a teen's and a parent's phone using
/// CloudKit zone sharing. There is no employer/law-enforcement pairing
/// path and no way to pair without both people taking a visible action —
/// the teen shows a QR code and the parent scans it; both apps then show
/// each other's name as the paired participant. Only the completed/missed
/// fact in `GuardianSyncEvent` is ever written into the shared zone — no
/// biometric data, frame, or landmark is stored in CloudKit.
@MainActor
final class GuardianPairingService: ObservableObject {
  enum PairingStatus: Equatable {
    case notPaired
    case working
    case awaitingAcceptance(URL)
    case paired(GuardianPairingInfo)
    case failed(String)
  }

  @Published private(set) var status: PairingStatus = .notPaired

  static let zoneName = "GuardianZone"
  static let checkEventRecordType = "GuardianCheckEvent"

  private let container = CKContainer.default()
  private(set) var sharedZoneID: CKRecordZone.ID?

  // MARK: - Teen side: create and display an invite

  func createInvite() async {
    status = .working
    do {
      let zone = CKRecordZone(zoneName: Self.zoneName)
      _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])

      let share = CKShare(recordZoneID: zone.zoneID)
      share[CKShare.SystemFieldKey.title] = "Sober Guardian Mode" as CKRecordValue
      share.publicPermission = .none

      let result = try await container.privateCloudDatabase.modifyRecords(
        saving: [share], deleting: [])
      guard case .success(let savedRecord) = result.saveResults[share.recordID],
        let savedShare = savedRecord as? CKShare,
        let url = savedShare.url
      else {
        status = .failed("Couldn't create a pairing invite. Check your connection and try again.")
        return
      }
      sharedZoneID = zone.zoneID
      status = .awaitingAcceptance(url)
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  func qrImage(for url: URL, scale: CGFloat = 10) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(url.absoluteString.utf8)
    filter.correctionLevel = "M"
    guard let outputImage = filter.outputImage else { return nil }
    let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }

  /// Call periodically while `.awaitingAcceptance` to notice when the
  /// parent has scanned and accepted. There is no push for "share accepted"
  /// on the owning side, so this polls the share's participant list.
  func refreshInviteStatus() async {
    guard case .awaitingAcceptance = status, let zoneID = sharedZoneID else { return }
    do {
      let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
      let record = try await container.privateCloudDatabase.record(for: shareID)
      guard let share = record as? CKShare else { return }
      let accepted = share.participants.first {
        $0.role == .privateUser && $0.acceptanceStatus == .accepted
      }
      guard let accepted else { return }
      let name = accepted.userIdentity.nameComponents.map {
        PersonNameComponentsFormatter().string(from: $0)
      }
      status = .paired(GuardianPairingInfo(participantName: name ?? "Your parent", pairedAt: Date()))
    } catch {
      // Not accepted yet, or a transient network error — stay in the
      // awaiting state rather than surfacing a false failure.
    }
  }

  // MARK: - Parent side: accept a scanned invite

  func acceptInvite(from url: URL) async {
    status = .working
    do {
      let metadata = try await fetchShareMetadata(for: url)
      let share = try await acceptShare(metadata: metadata)
      sharedZoneID = share.recordID.zoneID
      let name = metadata.ownerIdentity.nameComponents.map {
        PersonNameComponentsFormatter().string(from: $0)
      }
      status = .paired(GuardianPairingInfo(participantName: name ?? "Your teen", pairedAt: Date()))
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
    try await withCheckedThrowingContinuation { continuation in
      var didResume = false
      let operation = CKFetchShareMetadataOperation(shareURLs: [url])
      operation.perShareMetadataResultBlock = { _, result in
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success(let metadata):
          continuation.resume(returning: metadata)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
      operation.fetchShareMetadataResultBlock = { result in
        guard !didResume else { return }
        if case .failure(let error) = result {
          didResume = true
          continuation.resume(throwing: error)
        }
      }
      container.add(operation)
    }
  }

  private func acceptShare(metadata: CKShare.Metadata) async throws -> CKShare {
    try await withCheckedThrowingContinuation { continuation in
      var didResume = false
      let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
      operation.perShareResultBlock = { _, result in
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success(let share):
          continuation.resume(returning: share)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
      operation.acceptSharesResultBlock = { result in
        guard !didResume else { return }
        if case .failure(let error) = result {
          didResume = true
          continuation.resume(throwing: error)
        }
      }
      container.add(operation)
    }
  }

  // MARK: - Shared record I/O

  /// Writes the completed/missed fact to the shared zone. Both the teen
  /// (owner) and parent (participant) call this same path against their
  /// own view of the shared database, so either side's CKQuerySubscription
  /// sees new events regardless of who wrote them.
  func send(_ event: GuardianSyncEvent) async throws {
    guard let zoneID = sharedZoneID else {
      throw GuardianPairingError.notPaired
    }
    let record = CKRecord(
      recordType: Self.checkEventRecordType, recordID: CKRecord.ID(zoneID: zoneID))
    record["windowID"] = event.windowID as CKRecordValue
    record["outcome"] = event.outcome.rawValue as CKRecordValue
    record["occurredAt"] = event.occurredAt as CKRecordValue
    _ = try await database(for: zoneID).modifyRecords(saving: [record], deleting: [])
  }

  /// The teen's writes land in the private database (it owns the zone);
  /// the parent's writes land in the shared database (it's a participant).
  /// CloudKit reconciles both views of the same underlying zone.
  private func database(for zoneID: CKRecordZone.ID) -> CKDatabase {
    zoneID.ownerName == CKCurrentUserDefaultName
      ? container.privateCloudDatabase
      : container.sharedCloudDatabase
  }
}

enum GuardianPairingError: LocalizedError {
  case notPaired

  var errorDescription: String? {
    "Guardian Mode isn't paired yet."
  }
}
