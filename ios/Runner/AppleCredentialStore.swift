import Foundation
import LocalAuthentication
import Security

#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

// Shared by both Apple runners. The macOS project references this source directly.
protocol CredentialKeychain {
  func read(_ query: [String: Any]) -> (OSStatus, Data?)
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
  func add(_ attributes: [String: Any]) -> OSStatus
  func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemCredentialKeychain: CredentialKeychain {
  func read(_ query: [String: Any]) -> (OSStatus, Data?) {
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &value)
    return (status, value as? Data)
  }

  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    SecItemAdd(attributes as CFDictionary, nil)
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    SecItemDelete(query as CFDictionary)
  }
}

final class AppleCredentialStore {
  private let service: String
  private let keychain: CredentialKeychain

  init(service: String, keychain: CredentialKeychain = SystemCredentialKeychain()) {
    self.service = service
    self.keychain = keychain
  }

  func read(_ key: String) -> [String: String] {
    let account = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !account.isEmpty else { return ["status": "missing"] }
    var attributes = query(account)
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, data) = keychain.read(attributes)
    if status == errSecItemNotFound { return ["status": "missing"] }
    // A locked or damaged Keychain is not a logout. Preserve the stored account
    // and let Dart report unavailable instead of deleting credentials as missing.
    guard status == errSecSuccess,
          let data = data,
          let value = String(data: data, encoding: .utf8),
          !value.isEmpty else { return ["status": "unavailable"] }
    return ["status": "value", "value": value]
  }

  func write(_ key: String, value: String) -> Bool {
    let account = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !account.isEmpty else { return true }
    guard !value.isEmpty else { return delete(account) }
    let attributes = query(account)
    let changes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
    let status = keychain.update(attributes, attributes: changes)
    if status == errSecSuccess { return true }
    guard status == errSecItemNotFound else { return false }

    var newItem = attributes.merging(changes) { _, new in new }
    #if os(iOS)
    newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    #endif
    let addStatus = keychain.add(newItem)
    if addStatus == errSecDuplicateItem {
      // Another engine may have created the item between update and add.
      return keychain.update(attributes, attributes: changes) == errSecSuccess
    }
    return addStatus == errSecSuccess
  }

  func delete(_ key: String) -> Bool {
    let account = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !account.isEmpty else { return true }
    let status = keychain.delete(query(account))
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private func query(_ account: String) -> [String: Any] {
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseAuthenticationContext as String: authentication,
    ]
  }
}

final class AppleCredentialChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    let service = (Bundle.main.bundleIdentifier ?? "com.geqian.flyplayer.flyPlayer") + ".credentials"
    let store = AppleCredentialStore(service: service)
    channel = FlutterMethodChannel(name: "fly_player/secret_store", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      let key = arguments["key"] as? String ?? ""
      switch call.method {
      case "readCredential":
        result(store.read(key))
      case "writeCredential":
        guard let value = arguments["value"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "A credential value is required.", details: nil))
          return
        }
        result(store.write(key, value: value))
      case "deleteCredential":
        result(store.delete(key))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
