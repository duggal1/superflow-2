import Foundation
import LocalAuthentication
import Security

public struct ReflectionCredentials: Sendable {
    private let service: String
    public init(service: String = "Superflow.Reflection") { self.service = service }

    /// Existence check that never shows a system prompt. Navigation uses this so
    /// opening Intelligence cannot block on a login-keychain password dialog.
    /// An auth-blocked item still counts as saved; only "not found" is false.
    public func exists() -> Bool {
        var query = noPromptQuery
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
            || status == errSecAuthFailed
            || status == errSecInteractionNotAllowed
    }

    public func load() throws -> String? {
        var query = noPromptQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw Failure(status: status) }
        return key
    }

    public func save(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { try remove(); return }
        let values: [CFString: Any] = [kSecValueData: Data(key.utf8)]
        let status = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var query = identity
            query[kSecValueData] = Data(key.utf8)
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess { throw Failure(status: status) }
    }

    public func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    private var identity: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "api-key"]
    }

    /// Same no-prompt behavior as the retired kSecUseAuthenticationUIFail.
    private var noPromptQuery: [CFString: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = identity
        query[kSecUseAuthenticationContext] = context
        return query
    }

    private struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain access failed (\(status))." }
    }
}
