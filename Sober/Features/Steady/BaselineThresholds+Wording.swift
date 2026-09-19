import Foundation

/// The thresholds as they appear in copy.
///
/// Screens that say "five sessions" in a sentence would otherwise keep the old
/// word after `BaselineThresholds` moves — the same drift the constants exist
/// to stop, just in prose instead of logic.
extension BaselineThresholds {
  /// "five", in the person's language.
  static var requiredSessionsInWords: String {
    NumberFormatter.localizedString(from: NSNumber(value: requiredSessions), number: .spellOut)
  }

  /// "Five", for the start of a sentence.
  static var requiredSessionsInWordsCapitalized: String {
    requiredSessionsInWords.prefix(1).uppercased() + requiredSessionsInWords.dropFirst()
  }
}
