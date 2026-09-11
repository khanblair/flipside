import XCTest
@preconcurrency import Security
@testable import FlipsideCore

/// These tests exercise the real macOS Keychain for the current user (the app is
/// unsandboxed, per spec §11, so this is representative of production behavior).
/// To avoid polluting the production Keychain item, every test uses a dedicated
/// test service/account (production values with ".test" appended) via the
/// internal service/account-parameterized overloads on `KeychainKeyStore`, and
/// removes the test item in `tearDown()`.
final class KeychainKeyStoreTests: XCTestCase {
    private let testService = "com.flipside.app.sqlcipher-key.test"
    private let testAccount = "flipside-db-key.test"

    override func tearDown() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount
        ]
        SecItemDelete(query as CFDictionary)
        super.tearDown()
    }

    func testRandomKeyProducesExactlyRequestedLengthAndIsNotAllZero() {
        let key = KeychainKeyStore.randomKey(length: 32)

        XCTAssertEqual(key.count, 32)
        XCTAssertFalse(key.allSatisfy { $0 == 0 }, "randomKey should not produce an all-zero key")
    }

    func testSaveThenLoadRoundTripsTheExactSameBytes() throws {
        let key = KeychainKeyStore.randomKey(length: 32)

        try KeychainKeyStore.save(key, service: testService, account: testAccount)
        let loaded = try KeychainKeyStore.load(service: testService, account: testAccount)

        XCTAssertEqual(loaded, key)
    }

    func testLoadOrCreateKeyIsIdempotentAcrossRepeatedCalls() throws {
        let first = try KeychainKeyStore.loadOrCreateKey(service: testService, account: testAccount)
        let second = try KeychainKeyStore.loadOrCreateKey(service: testService, account: testAccount)

        XCTAssertEqual(first, second, "a second call must return the existing key, not generate a new one")
    }
}
