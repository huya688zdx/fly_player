import Foundation
import Security
import XCTest

#if os(macOS)
@testable import fly_player
#else
@testable import Runner
#endif

final class RunnerTests: XCTestCase {
  func testMissingCredentialIsDistinctFromLockedKeychain() {
    let keychain = FakeCredentialKeychain()
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    keychain.readStatus = errSecItemNotFound
    XCTAssertEqual(store.read("token")["status"], "missing")
    keychain.readStatus = errSecInteractionNotAllowed
    XCTAssertEqual(store.read("token")["status"], "unavailable")
    keychain.readStatus = errSecAuthFailed
    XCTAssertEqual(store.read("token")["status"], "unavailable")
  }

  func testReadReturnsUTF8AndNormalizesAccount() {
    let keychain = FakeCredentialKeychain()
    keychain.readStatus = errSecSuccess
    keychain.readData = "NAS 密码".data(using: .utf8)
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    XCTAssertEqual(store.read(" token "), ["status": "value", "value": "NAS 密码"])
    XCTAssertEqual(keychain.lastQuery[kSecAttrAccount as String] as? String, "token")
    XCTAssertEqual(keychain.lastQuery[kSecAttrService as String] as? String, "test.flyplayer")
  }

  func testCorruptStoredDataIsUnavailableRatherThanMissing() {
    let keychain = FakeCredentialKeychain()
    keychain.readStatus = errSecSuccess
    keychain.readData = Data([0xFF])
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    XCTAssertEqual(store.read("token")["status"], "unavailable")
    keychain.readData = nil
    XCTAssertEqual(store.read("token")["status"], "unavailable")
  }

  func testWriteUpdatesExistingCredentialWithoutDeletingIt() {
    let keychain = FakeCredentialKeychain()
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    XCTAssertTrue(store.write("token", value: "new value"))
    XCTAssertEqual(keychain.updatedData, Data("new value".utf8))
    XCTAssertEqual(keychain.addCount, 0)
    XCTAssertEqual(keychain.deleteCount, 0)
  }

  func testWriteCreatesMissingCredentialAndRetriesConcurrentInsert() {
    let keychain = FakeCredentialKeychain()
    keychain.updateStatuses = [errSecItemNotFound, errSecSuccess]
    keychain.addStatus = errSecDuplicateItem
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    XCTAssertTrue(store.write("token", value: "new value"))
    XCTAssertEqual(keychain.addCount, 1)
    XCTAssertEqual(keychain.updateCount, 2)
    XCTAssertEqual(keychain.deleteCount, 0)
  }

  func testLockedKeychainDoesNotReplaceExistingCredential() {
    let keychain = FakeCredentialKeychain()
    keychain.updateStatuses = [errSecInteractionNotAllowed]
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    XCTAssertFalse(store.write("token", value: "new value"))
    XCTAssertEqual(keychain.addCount, 0)
    XCTAssertEqual(keychain.deleteCount, 0)
  }

  func testDeleteMissingIsIdempotentAndDeleteFailureIsReported() {
    let keychain = FakeCredentialKeychain()
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    keychain.deleteStatus = errSecItemNotFound
    XCTAssertTrue(store.delete("token"))
    keychain.deleteStatus = errSecInteractionNotAllowed
    XCTAssertFalse(store.delete("token"))
  }

  func testEmptyValueDeletesAndBlankKeysDoNotQueryKeychain() {
    let keychain = FakeCredentialKeychain()
    let store = AppleCredentialStore(service: "test.flyplayer", keychain: keychain)

    XCTAssertTrue(store.write("token", value: ""))
    XCTAssertEqual(keychain.deleteCount, 1)
    XCTAssertEqual(store.read(" \n ")["status"], "missing")
    XCTAssertTrue(store.write(" ", value: "value"))
    XCTAssertTrue(store.delete(" "))
    XCTAssertEqual(keychain.readCount, 0)
    XCTAssertEqual(keychain.updateCount, 0)
    XCTAssertEqual(keychain.deleteCount, 1)
  }
}

private final class FakeCredentialKeychain: CredentialKeychain {
  var readStatus = errSecItemNotFound
  var readData: Data?
  var updateStatuses: [OSStatus] = [errSecSuccess]
  var addStatus = errSecSuccess
  var deleteStatus = errSecSuccess
  var lastQuery: [String: Any] = [:]
  var updatedData: Data?
  var readCount = 0
  var updateCount = 0
  var addCount = 0
  var deleteCount = 0

  func read(_ query: [String: Any]) -> (OSStatus, Data?) {
    lastQuery = query
    readCount += 1
    return (readStatus, readData)
  }

  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    lastQuery = query
    updatedData = attributes[kSecValueData as String] as? Data
    updateCount += 1
    return updateStatuses.count > 1 ? updateStatuses.removeFirst() : updateStatuses[0]
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    addCount += 1
    return addStatus
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    lastQuery = query
    deleteCount += 1
    return deleteStatus
  }
}
