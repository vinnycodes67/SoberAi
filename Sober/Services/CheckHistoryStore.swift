import Foundation

/// One line in History.
///
/// Deliberately thin. It records what a session was, when, whether the capture
/// was worth anything, and — for a check — which of the three states came out.
/// It carries no task measurements, no per-signal detail, and no risk score,
/// because History is a record for the person, not a second copy of the
/// measurement.
struct CheckHistoryEntry: Codable, Equatable, Identifiable, Sendable {
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

  private static let storeSchemaVersion = 1
  private static let fileName = "check-history-v1.json"

  private struct Document: Codable {
    var schemaVersion: Int
    var entries: [CheckHistoryEntry]
  }

  private let directoryURL: URL
  private let fileURL: URL

  init(directoryURL: URL? = nil) {
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
    fileURL = resolved.appendingPathComponent(Self.fileName, isDirectory: false)
  }

  /// Newest first.
  func list(now: Date = Date()) throws -> [CheckHistoryEntry] {
    // Prune on read as well as write. Otherwise an app that is opened but never
    // used again keeps showing entries past their retention window.
    Self.pruned(try loadDocument().entries, now: now)
  }

  func append(_ entry: CheckHistoryEntry, now: Date = Date()) throws {
    var document = try loadDocument()
    document.entries.removeAll { $0.id == entry.id }
    document.entries.append(entry)
    document.entries = Self.pruned(document.entries, now: now)
    try persist(document)
  }

  @discardableResult
  func deleteAll() throws -> Int {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
    let deletedCount = (try? loadDocument().entries.count) ?? 0
    try FileManager.default.removeItem(at: fileURL)
    return deletedCount
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
      return Document(schemaVersion: Self.storeSchemaVersion, entries: [])
    }
    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let document = try decoder.decode(Document.self, from: data)
    // An unreadable or future-version file must not take History down with it.
    guard document.schemaVersion == Self.storeSchemaVersion else {
      return Document(schemaVersion: Self.storeSchemaVersion, entries: [])
    }
    return document
  }

  private func persist(_ document: Document) throws {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    applyBestEffortFileProtection(to: directoryURL)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(document)
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
}
