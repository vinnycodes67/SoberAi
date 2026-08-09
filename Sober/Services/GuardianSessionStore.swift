import Foundation
import Security

protocol GuardianSessionStoring: Sendable {
  func load() throws -> GuardianSession?
  func save(_ session: GuardianSession) throws
  func delete() throws
}

struct KeychainGuardianSessionStore: GuardianSessionStoring {
  private let service = "com.soberprototype.app.guardian"
  private let account = "relationship-session-v1"

  func load() throws -> GuardianSession? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw GuardianSessionStoreError.keychain(status)
    }
    return try JSONDecoder().decode(GuardianSession.self, from: data)
  }

  func save(_ session: GuardianSession) throws {
    let data = try JSONEncoder().encode(session)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addition = baseQuery
      attributes.forEach { addition[$0.key] = $0.value }
      let addStatus = SecItemAdd(addition as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw GuardianSessionStoreError.keychain(addStatus) }
    } else if updateStatus != errSecSuccess {
      throw GuardianSessionStoreError.keychain(updateStatus)
    }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw GuardianSessionStoreError.keychain(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

enum GuardianSessionStoreError: LocalizedError {
  case keychain(OSStatus)

  var errorDescription: String? {
    "Guardian Mode could not access protected device storage."
  }
}
