import SwiftUI
import UIKit
import XCTest

@testable import Sober

/// The shared Curfew contract, the App Group store, the outbox, the copy, the
/// shield palette, and the public-build boundary. Together these pin the
/// brief's non-negotiables (`Docs/CURFEW_SHREY_BRIEF.md` §2): a check-in has no
/// result in it, nothing green, nothing paused that is the way home, and none
/// of it in the public app.
final class CurfewContractTests: XCTestCase {

  static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = losAngeles
    return calendar
  }

  let schedule = CurfewSchedule.standard(timeZone: CurfewContractTests.losAngeles)

  func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    let components = DateComponents(
      timeZone: Self.losAngeles, year: year, month: month, day: day, hour: hour, minute: minute
    )
    return Self.calendar.date(from: components)!
  }

  func night(evening day: Int) -> CurfewNight {
    CurfewPauseEvaluator.night(eveningOf: date(2026, 9, day, 12, 0), schedule: schedule)!
  }

  /// Every field populated so the encoder emits every key.
  func fullCheckIn(status: CurfewStatus = .checkedIn) -> CurfewCheckIn {
    CurfewCheckIn(
      id: UUID(),
      at: Date(timeIntervalSince1970: 1_788_000_000),
      status: status,
      latitude: 37.7749,
      longitude: -122.4194,
      horizontalAccuracyMeters: 12
    )
  }

  static func storedPropertyNames(of subject: Any) -> [String] {
    Mirror(reflecting: subject).children.compactMap(\.label)
  }

  static var repositoryRoot: URL {
    // SoberTests/CurfewContractTests.swift -> repository root.
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  // MARK: - A Sober result never unlocks

  func testCheckInCarriesExactlyTheDocumentedFields() {
    XCTAssertEqual(
      Self.storedPropertyNames(of: fullCheckIn()),
      ["id", "at", "status", "latitude", "longitude", "horizontalAccuracyMeters"]
    )
  }

  func testSharedStateCarriesExactlyTheDocumentedFields() {
    XCTAssertEqual(
      Self.storedPropertyNames(of: CurfewSharedState()),
      [
        "schedule", "pauseSelectionData", "allowSelectionData", "home", "tonight", "outbox",
        "guardianDisplayName", "safeRidePromiseSignedAt", "pendingRoute", "isShieldApplied",
        "shieldChangedAt",
      ]
    )
  }

  func testNoContractTypeHasAResultScoreOrTookCheckField() {
    let subjects: [Any] = [fullCheckIn(), CurfewSharedState(), CurfewTonight(nightID: "n"), schedule]
    let suspicious = ["result", "score", "outcome", "tookCheck", "screening", "signals", "requireCheck"]
    for subject in subjects {
      for name in Self.storedPropertyNames(of: subject) {
        for needle in suspicious {
          XCTAssertFalse(
            name.localizedCaseInsensitiveContains(needle),
            "\(type(of: subject)).\(name) looks like a Sober result reaching the contract"
          )
        }
      }
    }
  }

  func testStatusCasesAreExactlyTheFourTheGuardianCanSee() {
    XCTAssertEqual(
      CurfewStatus.allCases.map(\.rawValue),
      ["home", "checkedIn", "askedForRide", "noCheckInYet"]
    )
    XCTAssertEqual(CurfewStatus.reportable, [.checkedIn, .askedForRide])
    XCTAssertTrue(CurfewStatus.checkedIn.isReportable)
    XCTAssertTrue(CurfewStatus.askedForRide.isReportable)
    XCTAssertFalse(CurfewStatus.home.isReportable)
    XCTAssertFalse(CurfewStatus.noCheckInYet.isReportable)
  }

  /// Rule 1 and rule 5, checked against the source on disk: no Curfew file may
  /// reach for the screening engine, its outcome, history, or a "require a
  /// check" switch.
  func testCurfewSourcesNeverReferenceScreeningOutcomes() throws {
    let root = Self.repositoryRoot
    let candidates = [
      root.appendingPathComponent("Sober/Services/Curfew"),
      root.appendingPathComponent("Sober/Features/Curfew"),
      root.appendingPathComponent("Sober/Models/CurfewContract.swift"),
    ]
    let forbidden = [
      "ScreeningOutcome", "ScreeningEngine", "CheckHistoryStore", "signalsDetected",
      "noSignalsDetected", "requireSoberCheck", "requiresCheck",
    ]
    let fileManager = FileManager.default

    var swiftFiles: [URL] = []
    for candidate in candidates {
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
        throw XCTSkip("\(candidate.lastPathComponent) does not exist in this checkout")
      }
      if isDirectory.boolValue {
        let enumerator = fileManager.enumerator(at: candidate, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
          if url.pathExtension == "swift" { swiftFiles.append(url) }
        }
      } else {
        swiftFiles.append(candidate)
      }
    }
    XCTAssertFalse(swiftFiles.isEmpty, "Expected at least CurfewContract.swift")

    for url in swiftFiles {
      let source = try String(contentsOf: url, encoding: .utf8)
      for needle in forbidden {
        XCTAssertFalse(
          source.contains(needle),
          "\(url.path) references \(needle); a Sober result must never be a Curfew input"
        )
      }
    }
  }

  // MARK: - Codable

  func testScheduleRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(schedule)
    let decoded = try JSONDecoder().decode(CurfewSchedule.self, from: data)
    XCTAssertEqual(decoded, schedule)
  }

  func testCheckInRoundTripsThroughJSON() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let original = fullCheckIn(status: .askedForRide)
    let decoded = try decoder.decode(CurfewCheckIn.self, from: encoder.encode(original))
    XCTAssertEqual(decoded, original)
  }

  func testStatusRoundTripsThroughJSON() throws {
    for status in CurfewStatus.allCases {
      let data = try JSONEncoder().encode([status])
      XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"\(status.rawValue)\"]")
      let decoded = try JSONDecoder().decode([CurfewStatus].self, from: data)
      XCTAssertEqual(decoded, [status])
    }
  }

  func testEncodedCheckInHasExactlySixKeys() throws {
    let data = try JSONEncoder().encode(fullCheckIn())
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(
      Set(object.keys),
      ["id", "at", "status", "latitude", "longitude", "horizontalAccuracyMeters"]
    )
    XCTAssertEqual(object.count, 6)
  }

  func testStandardScheduleIsValid() {
    XCTAssertTrue(schedule.isValid)
    XCTAssertTrue(CurfewSchedule.standard().isValid)
    XCTAssertEqual(schedule.weeknight, DateComponents(hour: 23, minute: 0))
    XCTAssertEqual(schedule.weekend, DateComponents(hour: 0, minute: 30))
    XCTAssertEqual(schedule.recheckMinutes, 60)
    XCTAssertEqual(schedule.graceMinutes, 10)
  }

  func testWeekendEveningsAreFridayAndSaturday() {
    XCTAssertEqual(CurfewSchedule.weekendEveningWeekdays, [6, 7])
    XCTAssertEqual(schedule.curfewTime(forEveningWeekday: 6), schedule.weekend)
    XCTAssertEqual(schedule.curfewTime(forEveningWeekday: 7), schedule.weekend)
    XCTAssertEqual(schedule.curfewTime(forEveningWeekday: 1), schedule.weeknight)
    XCTAssertEqual(schedule.curfewTime(forEveningWeekday: 5), schedule.weeknight)
  }

  // MARK: - Shared state

  func testRecordAppendsToTonightAndOutbox() {
    var state = CurfewSharedState()
    let tuesday = night(evening: 8)
    let first = fullCheckIn()
    let second = fullCheckIn(status: .askedForRide)

    XCTAssertTrue(state.record(first, for: tuesday))
    XCTAssertTrue(state.record(second, for: tuesday))

    XCTAssertEqual(state.tonight?.nightID, tuesday.id)
    XCTAssertEqual(state.tonight?.checkIns, [first, second])
    XCTAssertEqual(state.outbox, [first, second])
    XCTAssertTrue(state.tonight?.askedForRide == true)
  }

  func testRecordStartsAFreshTonightWhenTheNightChanges() {
    var state = CurfewSharedState()
    let tuesday = night(evening: 8)
    let wednesday = night(evening: 9)
    let first = fullCheckIn()
    let second = fullCheckIn()

    state.record(first, for: tuesday)
    state.record(second, for: wednesday)

    XCTAssertEqual(state.tonight?.nightID, wednesday.id)
    XCTAssertEqual(state.tonight?.checkIns, [second])
    XCTAssertEqual(state.outbox, [first, second], "The outbox keeps both nights until delivered")
  }

  func testRecordRefusesNonReportableStatuses() {
    var state = CurfewSharedState()
    let tuesday = night(evening: 8)

    XCTAssertFalse(state.record(fullCheckIn(status: .home), for: tuesday))
    XCTAssertFalse(state.record(fullCheckIn(status: .noCheckInYet), for: tuesday))

    XCTAssertNil(state.tonight)
    XCTAssertTrue(state.outbox.isEmpty)
  }

  func testMarkDeliveredRemovesOnlyThoseIDs() {
    var state = CurfewSharedState()
    let tuesday = night(evening: 8)
    let a = fullCheckIn()
    let b = fullCheckIn()
    let c = fullCheckIn()
    for checkIn in [a, b, c] { state.record(checkIn, for: tuesday) }

    state.markDelivered([a.id, c.id])

    XCTAssertEqual(state.outbox, [b])
    XCTAssertEqual(state.tonight?.checkIns, [a, b, c], "Delivery does not rewrite tonight")
  }

  func testAppGroupStoreRoundTripsAndUpdateSaves() throws {
    let suiteName = "test.curfew.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let store = AppGroupCurfewStore(suiteName: suiteName)

    XCTAssertEqual(store.load(), CurfewSharedState(), "A fresh suite reads as empty")
    XCTAssertFalse(store.load().isConfigured)

    let tuesday = night(evening: 8)
    var state = CurfewSharedState(
      schedule: schedule,
      pauseSelectionData: Data([0x01, 0x02]),
      home: CurfewHomeReading(isHome: true, observedAt: date(2026, 9, 8, 22, 0)),
      guardianDisplayName: "Jordan",
      safeRidePromiseSignedAt: date(2026, 9, 1, 9, 0),
      pendingRoute: .checkIn,
      isShieldApplied: true,
      shieldChangedAt: date(2026, 9, 8, 23, 10)
    )
    state.record(fullCheckIn(), for: tuesday)
    try store.save(state)

    XCTAssertEqual(store.load(), state)
    XCTAssertTrue(store.load().isConfigured)

    let delivered = try store.update { shared -> Int in
      let ids = Set(shared.outbox.map(\.id))
      shared.markDelivered(ids)
      shared.pendingRoute = nil
      return ids.count
    }
    XCTAssertEqual(delivered, 1)
    XCTAssertTrue(store.load().outbox.isEmpty)
    XCTAssertNil(store.load().pendingRoute)
    XCTAssertEqual(store.load().tonight?.checkIns.count, 1)

    // A second instance over the same suite sees the same bytes.
    XCTAssertEqual(AppGroupCurfewStore(suiteName: suiteName).load(), store.load())
  }

  func testStoreWithUnavailableSuiteReadsEmptyAndRefusesToSave() throws {
    // Foundation returns nil for the app's own bundle identifier and for the
    // global domain; either proves the unavailable path.
    let candidates = [Bundle.main.bundleIdentifier, UserDefaults.globalDomain].compactMap { $0 }
    guard let unavailable = candidates.first(where: { UserDefaults(suiteName: $0) == nil }) else {
      throw XCTSkip("No suite name is refused by UserDefaults on this host")
    }
    let store = AppGroupCurfewStore(suiteName: unavailable)

    XCTAssertEqual(store.load(), CurfewSharedState())
    XCTAssertFalse(store.load().isConfigured)
    XCTAssertThrowsError(try store.save(CurfewSharedState(schedule: schedule))) { error in
      XCTAssertEqual(error as? CurfewStoreError, .appGroupUnavailable)
    }
  }

  // MARK: - Outbox

  actor RecordingSender: CurfewCheckInSending {
    enum Failure: Error { case refused }

    private(set) var sent: [CurfewCheckIn] = []
    private let failOnCall: Int?
    private let alwaysFail: Bool
    private var calls = 0

    init(failOnCall: Int? = nil, alwaysFail: Bool = false) {
      self.failOnCall = failOnCall
      self.alwaysFail = alwaysFail
    }

    func send(_ checkIn: CurfewCheckIn) async throws {
      calls += 1
      if alwaysFail || calls == failOnCall { throw Failure.refused }
      sent.append(checkIn)
    }
  }

  func seededStore(_ checkIns: [CurfewCheckIn]) -> InMemoryCurfewStore {
    var state = CurfewSharedState()
    for checkIn in checkIns { state.record(checkIn, for: night(evening: 8)) }
    return InMemoryCurfewStore(state: state)
  }

  func testFlusherStopsAtFirstFailureAndKeepsTheRestInOrder() async {
    let a = fullCheckIn()
    let b = fullCheckIn()
    let c = fullCheckIn()
    let store = seededStore([a, b, c])
    let sender = RecordingSender(failOnCall: 2)

    let delivered = await CurfewOutboxFlusher(store: store, sender: sender).flush()

    XCTAssertEqual(delivered, 1)
    let sent = await sender.sent
    XCTAssertEqual(sent, [a])
    XCTAssertEqual(store.load().outbox, [b, c])
  }

  func testFlusherWithAlwaysFailingSenderDeliversNothingAndKeepsAll() async {
    let checkIns = [fullCheckIn(), fullCheckIn()]
    let store = seededStore(checkIns)
    let sender = RecordingSender(alwaysFail: true)

    let delivered = await CurfewOutboxFlusher(store: store, sender: sender).flush()

    XCTAssertEqual(delivered, 0)
    let sent = await sender.sent
    XCTAssertTrue(sent.isEmpty)
    XCTAssertEqual(store.load().outbox, checkIns)
  }

  func testUnconfiguredSenderKeepsEverythingQueued() async {
    let checkIns = [fullCheckIn(), fullCheckIn(status: .askedForRide)]
    let store = seededStore(checkIns)

    let flusher = CurfewOutboxFlusher(store: store, sender: UnconfiguredCurfewCheckInSender())
    let delivered = await flusher.flush()

    XCTAssertEqual(delivered, 0)
    XCTAssertEqual(store.load().outbox, checkIns)
  }

  func testFlusherNeverSendsNonReportableItems() async {
    // Bypass `record` to plant statuses the teen's phone must never send.
    let reportable = fullCheckIn()
    let planted = [fullCheckIn(status: .home), reportable, fullCheckIn(status: .noCheckInYet)]
    let store = InMemoryCurfewStore(state: CurfewSharedState(outbox: planted))
    let sender = RecordingSender()

    let delivered = await CurfewOutboxFlusher(store: store, sender: sender).flush()

    XCTAssertEqual(delivered, 1)
    let sent = await sender.sent
    XCTAssertEqual(sent, [reportable])
    XCTAssertFalse(store.load().outbox.contains(reportable))
  }

  // MARK: - Copy

  func containsWholeWord(_ word: String, in text: String, caseInsensitive: Bool) -> Bool {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    let regex = try! NSRegularExpression(pattern: pattern, options: options)
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  func testCopyNeverUsesAForbiddenWord() {
    XCTAssertFalse(CurfewCopy.allStrings.isEmpty)
    for string in CurfewCopy.allStrings {
      let scrubbed = string.replacingOccurrences(of: "Safe Ride Promise", with: "")
      for word in CurfewCopy.forbiddenWords {
        XCTAssertFalse(
          containsWholeWord(word, in: scrubbed, caseInsensitive: true),
          "\"\(string)\" contains forbidden word \"\(word)\""
        )
      }
    }
  }

  func testCopyNeverUsesSoberAsAState() {
    for string in CurfewCopy.allStrings {
      XCTAssertFalse(
        containsWholeWord("sober", in: string, caseInsensitive: false),
        "\"\(string)\" uses lowercase \"sober\" as a state; only the app name is allowed"
      )
    }
  }

  func testEveryMentionOfPausingSaysWhatStillWorks() {
    XCTAssertTrue(CurfewCopy.notificationBody.hasPrefix(CurfewCopy.pausedTitle))
    let afterTitle = CurfewCopy.notificationBody.dropFirst(CurfewCopy.pausedTitle.count)
    XCTAssertTrue(afterTitle.contains(CurfewCopy.stillWorks), "pausedTitle must be followed by stillWorks")
    XCTAssertTrue(CurfewCopy.shieldSubtitle.contains("still work"))
    XCTAssertTrue(CurfewCopy.stillWorks.contains("still work"))

    let shieldLabels: Set<String> = [
      CurfewCopy.shieldTitle, CurfewCopy.shieldPrimaryButton, CurfewCopy.shieldSecondaryButton,
      CurfewCopy.notificationTitle,
    ]
    for string in CurfewCopy.allStrings where string.localizedCaseInsensitiveContains("pause") {
      if string == CurfewCopy.pausedTitle || shieldLabels.contains(string) { continue }
      XCTAssertTrue(string.contains("still work"), "\"\(string)\" mentions pausing without saying what still works")
    }
  }

  func testShieldCopyMatchesTheBrief() {
    XCTAssertEqual(CurfewCopy.pausedTitle, "Apps paused until you check in.")
    XCTAssertEqual(CurfewCopy.stillWorks, "Calls, messages, maps and rides still work.")
    XCTAssertEqual(CurfewCopy.shieldTitle, "Check-in due")
    XCTAssertEqual(CurfewCopy.safeRidePromise(guardianName: "Jordan"), "Jordan promised: no questions tonight.")
    XCTAssertEqual(CurfewCopy.safeRidePromise(guardianName: "  "), "Your guardian promised: no questions tonight.")
  }

  // MARK: - Palette

  func rgb(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    return (red, green, blue)
  }

  func assertSameColour(_ hex: UInt32, _ design: Color, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(Color(dsHex: hex), design, "CurfewShieldPalette.\(name) drifted from DSPalette", file: file, line: line)
    let shield = rgb(Color(dsHex: hex))
    let expected = rgb(design)
    XCTAssertEqual(shield.red, expected.red, accuracy: 0.001, name, file: file, line: line)
    XCTAssertEqual(shield.green, expected.green, accuracy: 0.001, name, file: file, line: line)
    XCTAssertEqual(shield.blue, expected.blue, accuracy: 0.001, name, file: file, line: line)
  }

  func testShieldPaletteMatchesDesignKit() {
    assertSameColour(CurfewShieldPalette.background, DSPalette.background, "background")
    assertSameColour(CurfewShieldPalette.textPrimary, DSPalette.textPrimary, "textPrimary")
    assertSameColour(CurfewShieldPalette.textSecondary, DSPalette.textSecondary, "textSecondary")
    assertSameColour(CurfewShieldPalette.accent, DSPalette.accent, "accent")
    assertSameColour(CurfewShieldPalette.onAccent, DSPalette.onAccent, "onAccent")
  }

  func testShieldPaletteHasNoGreen() {
    let values: [(String, UInt32)] = [
      ("background", CurfewShieldPalette.background),
      ("textPrimary", CurfewShieldPalette.textPrimary),
      ("textSecondary", CurfewShieldPalette.textSecondary),
      ("accent", CurfewShieldPalette.accent),
      ("onAccent", CurfewShieldPalette.onAccent),
    ]
    for (name, hex) in values {
      let red = (hex >> 16) & 0xFF
      let green = (hex >> 8) & 0xFF
      let blue = hex & 0xFF
      XCTAssertFalse(green > red && green > blue, "CurfewShieldPalette.\(name) reads as green")
    }
  }

  // MARK: - Public boundary at runtime

  func testPublicHostEmbedsNoCurfewExtensionOrCapability() throws {
    let bundle = Bundle.main
    guard bundle.bundleIdentifier == "com.soberprototype.app" else {
      throw XCTSkip("Not hosted by the public app (\(bundle.bundleIdentifier ?? "nil"))")
    }

    // A test host carries its own `SoberTests.xctest` in PlugIns; the claim is
    // that no app extension, Curfew or otherwise, rides along with the app.
    if let plugIns = bundle.builtInPlugInsURL,
      let contents = try? FileManager.default.contentsOfDirectory(atPath: plugIns.path)
    {
      let extensions = contents.filter { $0.hasSuffix(".appex") }
      XCTAssertTrue(extensions.isEmpty, "Public app embeds extensions: \(extensions)")
      XCTAssertFalse(contents.contains { $0.hasPrefix("Curfew") }, "Curfew bundle in public app: \(contents)")
    }

    let info = bundle.infoDictionary ?? [:]
    XCTAssertNil(info["NSSupportsLiveActivities"], "Public app declares Live Activities")
    XCTAssertNil(info["CFBundleURLTypes"], "Public app declares a URL scheme")
    XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"])
    XCTAssertNil(info["NSLocationWhenInUseUsageDescription"])
  }
}
