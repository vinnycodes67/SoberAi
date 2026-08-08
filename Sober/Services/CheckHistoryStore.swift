import Foundation

enum CheckHistoryStoreError: Error, Equatable, LocalizedError {
  case duplicateEntry(UUID)
  case unsupportedEntrySchema(Int)
  case unsupportedStoreSchema(Int)
  case archiveQuarantined(fileName: String)
  case quarantineFailed(fileName: String)

  var errorDescription: String? {
    switch self {
    case .duplicateEntry:
      "Saved History contained a duplicate entry. The original archive was preserved for recovery."
    case .unsupportedEntrySchema, .unsupportedStoreSchema:
      "Saved History was created by an unsupported version of Sober. The original archive was preserved for recovery."
    case .archiveQuarantined:
      "Some saved History could not be loaded. The original archive was preserved for recovery."
    case .quarantineFailed:
      "Some saved History could not be loaded or safely preserved."
    }
  }
}

/// One line in History.
///
/// Deliberately thin. It records what a session was, when, whether the capture
/// was worth anything, and — for a check — which of the three states came out.
/// It carries no task measurements, no per-signal detail, and no risk score,
/// because History is a record for the person, not a second copy of the
/// measurement.
struct CheckHistoryEntry: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 1

  enum Kind: String, Codable, Sendable {
    case baseline
    case check
  }

  /// Mirrors `ScreeningResultState` without importing its scoring semantics
  /// into a storage type. `nil` for a baseline session, which has no verdict.
  enum Outcome: String, Codable, Sendable {
    case signalsDetected
    case inconclusive
    case noSignalsDetected
  }

  let id: UUID
  let startedAt: Date
  let kind: Kind
  let outcome: Outcome?
  let qualityScore: Double
  let completedAllTasks: Bool
  let schemaVersion: Int

  init(
    id: UUID,
    startedAt: Date,
    kind: Kind,
    outcome: Outcome?,
    qualityScore: Double,
    completedAllTasks: Bool,
    schemaVersion: Int = CheckHistoryEntry.currentSchemaVersion
  ) {
    self.id = id
    self.startedAt = startedAt
    self.kind = kind
    self.outcome = outcome
    self.qualityScore = qualityScore
    self.completedAllTasks = completedAllTasks
    self.schemaVersion = schemaVersion
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case startedAt
    case kind
    case outcome
    case qualityScore
    case completedAllTasks
    case schemaVersion
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    startedAt = try values.decode(Date.self, forKey: .startedAt)
    kind = try values.decode(Kind.self, forKey: .kind)
    outcome = try values.decodeIfPresent(Outcome.self, forKey: .outcome)
    qualityScore = try values.decode(Double.self, forKey: .qualityScore)
    completedAllTasks = try values.decode(Bool.self, forKey: .completedAllTasks)
    // The co-founder checkpoint briefly wrote entries before record-level
    // versioning landed. Those records are schema 1, not corrupt data.
    schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
      ?? Self.currentSchemaVersion
  }
}

/// History kept on this iPhone, independent of research consent.
///
/// The research archive only stores a check when someone has opted into
/// research, which is correct for research but meant a public build recorded no
/// checks at all — History would have shown baselines forever and nothing else.
/// These are different purposes with different lifetimes, so they are different
/// stores rather than one store with a flag.
///
/// ## Retention
///
/// Bounded by both age and count, pruned on every write. A permanent, growing
/// record of when someone checked themselves is a liability: it is the thing
/// another person would ask to see. Ninety days is enough to look back over a
/// season without becoming a dossier, and the cap stops a heavy user
/// accumulating an unbounded file.
actor CheckHistoryStore {
  static let retentionDays = 90
  static let maximumEntries = 100

  static let currentStoreSchemaVersion = 1
  static let currentFileName = "check-history-v1.json"
  static let quarantineDirectoryName = "Quarantine"

  private struct Document: Codable {
    var schemaVersion: Int
    var entries: [CheckHistoryEntry]
  }

  private let directoryURL: URL
  private let fileURL: URL
  private let quarantineID: @Sendable () -> String

  init(
    directoryURL: URL? = nil,
    quarantineID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) {
    let resolved: URL
    if let directoryURL {
      resolved = directoryURL
    } else {
      let applicationSupport =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      resolved = applicationSupport
        .appendingPathComponent("Sober", isDirectory: true)
        .appendingPathComponent("History", isDirectory: true)
    }
    self.directoryURL = resolved
    fileURL = resolved.appendingPathComponent(Self.currentFileName, isDirectory: false)
    self.quarantineID = quarantineID
  }

  /// Newest first.
  func list(now: Date = Date()) throws -> [CheckHistoryEntry] {
    // Prune on read as well as write. Otherwise an app that is opened but never
    // used again keeps retaining entries past their retention window on disk.
    var document = try loadDocument()
    let retained = Self.pruned(document.entries, now: now)
    if retained != document.entries {
      document.entries = retained
      try persist(document)
    }
    return retained
  }

  func append(_ entry: CheckHistoryEntry, now: Date = Date()) throws {
    guard entry.schemaVersion == CheckHistoryEntry.currentSchemaVersion else {
      throw CheckHistoryStoreError.unsupportedEntrySchema(entry.schemaVersion)
    }
    var document = try loadDocument()
    document.entries.removeAll { $0.id == entry.id }
    document.entries.append(entry)
    document.entries = Self.pruned(document.entries, now: now)
    try persist(document)
  }

  /// Deletes active and quarantined copies without requiring either to decode.
  @discardableResult
  func deleteAll() throws -> Int {
    guard FileManager.default.fileExists(atPath: directoryURL.path) else { return 0 }
    let deletedCount = bestEffortEntryIDs().count
    try FileManager.default.removeItem(at: directoryURL)
    return deletedCount
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

  private static func pruned(_ entries: [CheckHistoryEntry], now: Date) -> [CheckHistoryEntry] {
    let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
    return
      entries
      .filter { $0.startedAt >= cutoff }
      .sorted { $0.startedAt > $1.startedAt }
      .prefix(maximumEntries)
      .map { $0 }
  }

  private func loadDocument() throws -> Document {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return Document(schemaVersion: Self.currentStoreSchemaVersion, entries: [])
    }

    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      try quarantineAndThrow()
    }

    do {
      let decoder = Self.makeDecoder()
      let document = try decoder.decode(Document.self, from: data)
      guard document.schemaVersion == Self.currentStoreSchemaVersion else {
        throw CheckHistoryStoreError.unsupportedStoreSchema(document.schemaVersion)
      }
      try validate(document.entries)
      return document
    } catch {
      try quarantineAndThrow()
    }
  }

  private func validate(_ entries: [CheckHistoryEntry]) throws {
    var identifiers = Set<UUID>()
    for entry in entries {
      guard entry.schemaVersion == CheckHistoryEntry.currentSchemaVersion else {
        throw CheckHistoryStoreError.unsupportedEntrySchema(entry.schemaVersion)
      }
      guard identifiers.insert(entry.id).inserted else {
        throw CheckHistoryStoreError.duplicateEntry(entry.id)
      }
    }
  }

  private func quarantineAndThrow() throws -> Never {
    let fileManager = FileManager.default
    let quarantineURL = directoryURL.appendingPathComponent(
      Self.quarantineDirectoryName,
      isDirectory: true
    )
    do {
      try fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
      let stem = fileURL.deletingPathExtension().lastPathComponent
      let destination = quarantineURL.appendingPathComponent(
        "\(stem)-\(quarantineID()).json"
      )
      try fileManager.moveItem(at: fileURL, to: destination)
      applyBestEffortFileProtection(to: destination)
      throw CheckHistoryStoreError.archiveQuarantined(fileName: destination.lastPathComponent)
    } catch let error as CheckHistoryStoreError {
      throw error
    } catch {
      throw CheckHistoryStoreError.quarantineFailed(fileName: fileURL.lastPathComponent)
    }
  }

  private func persist(_ document: Document) throws {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    applyBestEffortFileProtection(to: directoryURL)

    let data = try Self.makeEncoder().encode(document)
    try data.write(to: fileURL, options: .atomic)
    applyBestEffortFileProtection(to: fileURL)
  }

  private func bestEffortEntryIDs() -> Set<UUID> {
    guard let data = try? Data(contentsOf: fileURL),
      let document = try? Self.makeDecoder().decode(Document.self, from: data)
    else { return [] }
    return Set(document.entries.map(\.id))
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func applyBestEffortFileProtection(to url: URL) {
    #if os(iOS) || os(tvOS) || os(watchOS)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    #endif
  }
}
