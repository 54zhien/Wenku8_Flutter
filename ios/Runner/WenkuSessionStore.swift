import Foundation
import Security

/// Stores only the opaque session, never a username or password.
struct WenkuSessionStore {
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "wenku8") + ".session",
     kSecAttrAccount as String: "PHPSESSID"]
  }

  func read() throws -> String? {
    var search = query
    search[kSecReturnData as String] = true
    search[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(search as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
      let value = String(data: data, encoding: .utf8),
      value.range(of: #"^[A-Za-z0-9,-]{8,256}$"#, options: .regularExpression) != nil
    else { throw WenkuProtocolError.invalidResponse }
    return value
  }

  func write(_ value: String?) throws {
    guard let value else {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw WenkuProtocolError.invalidResponse }
      return
    }
    let data = Data(value.utf8)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var addition = query
      addition[kSecValueData as String] = data
      addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw WenkuProtocolError.invalidResponse }
    } else if status != errSecSuccess { throw WenkuProtocolError.invalidResponse }
  }
}
