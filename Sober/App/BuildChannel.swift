import Foundation

/// Compile-time separation between the public App Store build and the internal
/// founder/research build.
///
/// This is deliberately a compilation condition rather than a runtime flag. A
/// runtime switch can fail open, and it leaves internal-only routes reachable in
/// the binary that ships to users. `INTERNAL_BUILD` is defined only for the
/// Debug configuration in `project.yml`; a Release build cannot turn it on.
enum BuildChannel {
  /// True only when compiled with `INTERNAL_BUILD`.
  ///
  /// Gates the founder preview, the Research Center, raw export, and any other
  /// surface that must never appear in App Store navigation.
  static let allowsInternalTools: Bool = {
    #if INTERNAL_BUILD
    return true
    #else
    return false
    #endif
  }()
}
