import Foundation

enum ResearchSessionStoreError: Error, Equatable, LocalizedError {
  case duplicateSession(ResearchSessionID)
  case unsupportedSessionSchema(Int)
  case unsupportedStoreSchema(Int)

  var errorDescription: String? {
    switch self {
    case .duplicateSession(let sessionID):
      "Research session already exists: \(sessionID.rawValue)"
    case .unsupportedSessionSchema(let version):
      "Unsupported research session schema version: \(version)"
    case .unsupportedStoreSchema(let version):
      "Unsupported research store schema version: \(version)"
    }
  }
}

/// Actor isolation prevents overlapping read-modify-write operations from
/// dropping sessions when multiple features record at the same time.
actor ResearchSessionStore {
  private static let storeSchemaVersion = 1
  private static let fileName = "research-sessions-v1.json"

  private let directoryURL: URL
  private let fileURL: URL

  init(directoryURL: URL? = nil) {
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
    fileURL = resolvedDirectory.appendingPathComponent(Self.fileName, isDirectory: false)
  }

  func list() throws -> [ResearchSessionEnvelope] {
    try loadDocument().sessions.sorted(by: Self.sessionSort)
  }

  func append(_ session: ResearchSessionEnvelope) throws {
    guard session.schemaVersion == ResearchSessionEnvelope.currentSchemaVersion else {
      throw ResearchSessionStoreError.unsupportedSessionSchema(session.schemaVersion)
    }

    var document = try loadDocument()
    guard !document.sessions.contains(where: { $0.sessionID == session.sessionID }) else {
      throw ResearchSessionStoreError.duplicateSession(session.sessionID)
    }

    document.sessions.append(session)
    document.sessions.sort(by: Self.sessionSort)
    try persist(document)
  }

  @discardableResult
  func delete(sessionID: ResearchSessionID) throws -> Bool {
    var document = try loadDocument()
    let originalCount = document.sessions.count
    document.sessions.removeAll(where: { $0.sessionID == sessionID })

    guard document.sessions.count != originalCount else { return false }
    try persist(document)
    return true
  }

  /// Removes the local research archive and returns the number of sessions
  /// that were deleted. A missing archive is already an empty store.
  @discardableResult
  func deleteAll() throws -> Int {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
    // Deletion must remain available even if an interrupted or future-version
    // archive cannot be decoded. In that case the count is unknown (zero).
    let deletedCount = (try? loadDocument().sessions.count) ?? 0
    try FileManager.default.removeItem(at: fileURL)
    return deletedCount
  }

  func exportPayload(exportedAt: Date = Date()) throws -> ResearchSessionExportPayload {
    ResearchSessionExportPayload(
      exportedAt: exportedAt,
      sessions: try list()
    )
  }

  func exportData(exportedAt: Date = Date()) throws -> Data {
    try Self.makeEncoder().encode(exportPayload(exportedAt: exportedAt))
  }

  private func loadDocument() throws -> ResearchSessionStoreDocument {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return ResearchSessionStoreDocument(
        schemaVersion: Self.storeSchemaVersion,
        sessions: []
      )
    }

    let data = try Data(contentsOf: fileURL)
    let document = try Self.makeDecoder().decode(ResearchSessionStoreDocument.self, from: data)
    guard document.schemaVersion == Self.storeSchemaVersion else {
      throw ResearchSessionStoreError.unsupportedStoreSchema(document.schemaVersion)
    }
    return document
  }

  private func persist(_ document: ResearchSessionStoreDocument) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    applyBestEffortFileProtection(to: directoryURL)

    let data = try Self.makeEncoder().encode(document)
    try data.write(to: fileURL, options: .atomic)
    applyBestEffortFileProtection(to: fileURL)
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

private struct ResearchSessionStoreDocument: Codable {
  let schemaVersion: Int
  var sessions: [ResearchSessionEnvelope]
}
