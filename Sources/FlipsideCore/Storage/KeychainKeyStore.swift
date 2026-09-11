import Foundation
@preconcurrency import Security

public enum KeychainError: Error {
    case saveFailed
    case notFound
}

/// Manages the SQLCipher database encryption key in the macOS Keychain.
///
/// Per spec §9.3: the key is generated once at first launch, stored via the
/// Security framework's generic-password APIs (`SecItemAdd`/`SecItemCopyMatching`),
/// and retrieved at subsequent launches. There is no password prompt, no
/// hardcoded key, and no derivation from a user-typed password. The app is not
/// sandboxed (spec §11), so no special Keychain-access-group entitlement is
/// required for these calls to work.
public enum KeychainKeyStore {
    static let service = "com.flipside.app.sqlcipher-key"
    static let account = "flipside-db-key"

    /// Returns the existing SQLCipher key from the Keychain if present;
    /// otherwise generates a new 32-byte key, saves it, and returns it.
    public static func loadOrCreateKey() throws -> Data {
        try loadOrCreateKey(service: service, account: account)
    }

    /// Generates `length` cryptographically random bytes via `SecRandomCopyBytes`.
    public static func randomKey(length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, length, buffer.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with OSStatus \(status)")
        return Data(bytes)
    }

    /// Saves `key` as a generic-password Keychain item, replacing any existing
    /// item for the same service/account first — safe to call more than once.
    public static func save(_ key: Data) throws {
        try save(key, service: service, account: account)
    }

    /// Loads the previously saved key. Throws `.notFound` if no item exists.
    public static func load() throws -> Data {
        try load(service: service, account: account)
    }

    // MARK: - Internal, service/account-parameterized implementations
    //
    // These overloads exist so tests can exercise the real logic above against
    // a dedicated test service/account rather than the production Keychain item.

    static func loadOrCreateKey(service: String, account: String) throws -> Data {
        if let existingKey = try? load(service: service, account: account) {
            return existingKey
        }
        let newKey = randomKey(length: 32)
        try save(newKey, service: service, account: account)
        return newKey
    }

    static func save(_ key: Data, service: String, account: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Ignore the result: it's fine if there was nothing to delete.
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    static func load(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.notFound
        }
        return data
    }
}
