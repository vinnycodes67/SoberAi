import Foundation

enum ResearchSessionStoreError: Error, Equatable, LocalizedError {
  case duplicateSession(ResearchSessionID)
  case unsupportedSessionSchema(Int)
  case unsupportedStoreSchema(Int)
  case archiveQuarantined(fileName: String)
  case quarantineFailed(fileName: String)

  var errorDescription: String? {
    switch self {
    case .duplicateSession(let sessionID):
      "Research session already exists: \(sessionID.rawValue)"
    case .unsupportedSessionSchema(let version):
      "Unsupported research session schema version: \(version)"
    case .unsupportedStoreSchema(let version):
      "Unsupported research store schema version: \(version)"
    case .archiveQuarantined:
      "Some saved history could not be loaded. The original archive was preserved for recovery."
    case .quarantineFailed:
      "Some saved history could not be loaded or safely preserved."
    }
  }
}

/// Versioned local archive for baseline and history records. Actor isolation
/// prevents overlapping read-modify-write operations from dropping sessions.
actor ResearchSessionStore {
  static let currentStoreSchemaVersion = 2
  static let currentFileName = "research-sessions-v2.json"
  static let legacyFileName = "research-sessions-v1.json"
  static let quarantineDirectoryName = "Quarantine"

  private let directoryURL: URL
  private let currentFileURL: URL
  private let legacyFileURL: URL
  private let quarantineID: @Sendable () -> String

  init(
    directoryURL: URL? = nil,
    quarantineID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) {
    let resolvedDirectory: URL
    if let directoryURL {
      resolvedDirectory = directoryURL
    } else {
      let applicationSupport =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      resolvedDirectory = applicationSupport
        .appendingPathComponent("Sober", isDirectory: true)
        .appendingPathComponent("Research", isDirectory: true)
    }

    self.directoryURL = resolvedDirectory
    currentFileURL = resolvedDirectory.appendingPathComponent(Self.currentFileName)
    legacyFileURL = resolvedDirectory.appendingPathComponent(Self.legacyFileName)
    self.quarantineID = quarantineID
  }

  func list() throws -> [ResearchSessionEnvelope] {
    try loadDocument().records.sorted(by: Self.sessionSort)
  }

  func append(_ session: ResearchSessionEnvelope) throws {
    guard session.schemaVersion == ResearchSessionEnvelope.currentSchemaVersion else {
      throw ResearchSessionStoreError.unsupportedSessionSchema(session.schemaVersion)
    }

    var document = try loadDocument()
    guard !document.records.contains(where: { $0.sessionID == session.sessionID }) else {
      throw ResearchSessionStoreError.duplicateSession(session.sessionID)
    }

    document.records.append(session)
    document.records.sort(by: Self.sessionSort)
    try persist(document)
  }

  @discardableResult
  func delete(sessionID: ResearchSessionID) throws -> Bool {
    var document = try loadDocument()
    let originalCount = document.records.count
    document.records.removeAll(where: { $0.sessionID == sessionID })

    guard document.records.count != originalCount else { return false }
    try persist(document)
    return true
  }

  /// Deletes active, legacy, and quarantined copies. A corrupt archive remains
  /// deletable because deletion never depends on decoding it first.
  @discardableResult
  func deleteAll() throws -> Int {
    guard FileManager.default.fileExists(atPath: directoryURL.path) else { return 0 }
    let deletedCount = bestEffortSessionIDs().count
    try FileManager.default.removeItem(at: directoryURL)
    return deletedCount
  }

  func exportPayload(exportedAt: Date = Date()) throws -> ResearchSessionExportPayload {
    ResearchSessionExportPayload(exportedAt: exportedAt, sessions: try list())
  }

  func exportData(exportedAt: Date = Date()) throws -> Data {
    try Self.makeEncoder().encode(exportPayload(exportedAt: exportedAt))
  }

  func quarantinedArchiveURLs() -> [URL] {
    let quarantineURL = directoryURL.appendingPathComponent(
      Self.quarantineDirectoryName,
      isDirectory: true
    )
    return (try? FileManager.default.contentsOfDirectory(
      at: quarantineURL,
      includingPropertiesForKeys: nil
    ))?.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) ?? []
  }

  private func loadDocument() throws -> ResearchSessionStoreDocumentV2 {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: currentFileURL.path) {
      let document = try decodeAndMigrate(at: currentFileURL)
      if fileManager.fileExists(atPath: legacyFileURL.path) {
        try? fileManager.removeItem(at: legacyFileURL)
      }
      return document
    }

    if fileManager.fileExists(atPath: legacyFileURL.path) {
      let migrated = try decodeAndMigrate(at: legacyFileURL)
      try persist(migrated)
      try fileManager.removeItem(at: legacyFileURL)
      return migrated
    }

    return ResearchSessionStoreDocumentV2(
      schemaVersion: Self.currentStoreSchemaVersion,
      records: []
    )
  }

  private func decodeAndMigrate(at sourceURL: URL) throws -> ResearchSessionStoreDocumentV2 {
    let data: Data
    do {
      data = try Data(contentsOf: sourceURL)
    } catch {
      try quarantineAndThrow(sourceURL)
    }

    let migrated: ResearchSessionStoreDocumentV2
    let sourceSchemaVersion: Int
    do {
      let header = try Self.makeDecoder().decode(StoreSchemaHeader.self, from: data)
      sourceSchemaVersion = header.schemaVersion
      switch header.schemaVersion {
      case Self.currentStoreSchemaVersion:
        migrated = try Self.makeDecoder().decode(ResearchSessionStoreDocumentV2.self, from: data)
      case 1:
        let legacy = try Self.makeDecoder().decode(ResearchSessionStoreDocumentV1.self, from: data)
        migrated = ResearchSessionStoreDocumentV2(
          schemaVersion: Self.currentStoreSchemaVersion,
          records: legacy.sessions
        )
      default:
        throw ResearchSessionStoreError.unsupportedStoreSchema(header.schemaVersion)
      }
      try validate(migrated.records)
    } catch {
      try quarantineAndThrow(sourceURL)
    }

    if sourceURL == currentFileURL, sourceSchemaVersion != Self.currentStoreSchemaVersion {
      try persist(migrated)
    }
    return migrated
  }

  private func validate(_ records: [ResearchSessionEnvelope]) throws {
    var sessionIDs = Set<ResearchSessionID>()
    for record in records {
      guard record.schemaVersion == ResearchSessionEnvelope.currentSchemaVersion else {
        throw ResearchSessionStoreError.unsupportedSessionSchema(record.schemaVersion)
      }
      guard sessionIDs.insert(record.sessionID).inserted else {
        throw ResearchSessionStoreError.duplicateSession(record.sessionID)
      }
    }
  }

  private func quarantineAndThrow(_ sourceURL: URL) throws -> Never {
    let fileManager = FileManager.default
    let quarantineURL = directoryURL.appendingPathComponent(
      Self.quarantineDirectoryName,
      isDirectory: true
    )
    do {
      try fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
      let stem = sourceURL.deletingPathExtension().lastPathComponent
      let destination = quarantineURL.appendingPathComponent(
        "\(stem)-\(quarantineID()).json"
      )
      try fileManager.moveItem(at: sourceURL, to: destination)
      applyBestEffortFileProtection(to: destination)
      throw ResearchSessionStoreError.archiveQuarantined(fileName: destination.lastPathComponent)
    } catch let error as ResearchSessionStoreError {
      throw error
    } catch {
      throw ResearchSessionStoreError.quarantineFailed(fileName: sourceURL.lastPathComponent)
    }
  }

  private func persist(_ document: ResearchSessionStoreDocumentV2) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    applyBestEffortFileProtection(to: directoryURL)

    let data = try Self.makeEncoder().encode(document)
    try data.write(to: currentFileURL, options: .atomic)
    applyBestEffortFileProtection(to: currentFileURL)
  }

  private func bestEffortSessionIDs() -> Set<ResearchSessionID> {
    var result = Set<ResearchSessionID>()
    for url in [currentFileURL, legacyFileURL] {
      guard let data = try? Data(contentsOf: url),
        let header = try? Self.makeDecoder().decode(StoreSchemaHeader.self, from: data)
      else { continue }

      if header.schemaVersion == Self.currentStoreSchemaVersion,
        let document = try? Self.makeDecoder().decode(ResearchSessionStoreDocumentV2.self, from: data)
      {
        result.formUnion(document.records.map(\.sessionID))
      } else if header.schemaVersion == 1,
        let document = try? Self.makeDecoder().decode(ResearchSessionStoreDocumentV1.self, from: data)
      {
        result.formUnion(document.sessions.map(\.sessionID))
      }
    }
    return result
  }

  private func applyBestEffortFileProtection(to url: URL) {
    #if os(iOS) || os(tvOS) || os(watchOS)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    #endif
  }

  private static func sessionSort(
    _ left: ResearchSessionEnvelope,
    _ right: ResearchSessionEnvelope
  ) -> Bool {
    if left.startedAt == right.startedAt {
      return left.sessionID.rawValue < right.sessionID.rawValue
    }
    return left.startedAt < right.startedAt
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    JSONDecoder()
  }
}

private struct StoreSchemaHeader: Decodable {
  let schemaVersion: Int
}

private struct ResearchSessionStoreDocumentV1: Codable {
  let schemaVersion: Int
  var sessions: [ResearchSessionEnvelope]
}

private struct ResearchSessionStoreDocumentV2: Codable {
  let schemaVersion: Int
  var records: [ResearchSessionEnvelope]
}
