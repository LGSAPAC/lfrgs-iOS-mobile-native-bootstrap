import Foundation

#if canImport(Security)
import Security
#endif

/// Persists the signed-in user's tokens between launches.
public protocol TokenStore: Sendable {
    func load() throws -> OAuthTokens?
    func save(_ tokens: OAuthTokens) throws
    func clear() throws
}

/// Keeps tokens in memory only. For tests and SwiftUI previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: OAuthTokens?

    public init(_ tokens: OAuthTokens? = nil) { self.tokens = tokens }

    public func load() throws -> OAuthTokens? { lock.withLock { tokens } }
    public func save(_ tokens: OAuthTokens) throws { lock.withLock { self.tokens = tokens } }
    public func clear() throws { lock.withLock { tokens = nil } }
}

#if canImport(Security)
/// Stores tokens in the Keychain as one generic-password item.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable after the first unlock (so a
/// background refresh works), never synced to iCloud, and not restored to another device.
public struct KeychainTokenStore: TokenStore {
    public enum KeychainError: Error, Equatable { case status(OSStatus) }

    let service: String
    let account: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "LiferayKit", account: String = "oauth-tokens") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> OAuthTokens? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
#endif
