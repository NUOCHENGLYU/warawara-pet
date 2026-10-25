import Foundation
import Security

/// Where the device token lives. The token itself is never logged and
/// never written to the mailbox file — only the Keychain (or the
/// in-memory stand-in used by tests).
protocol BottleMailCredentialStoring {
    func loadCredential() -> BottleMailCredential?
    func saveCredential(_ credential: BottleMailCredential) throws
    func clearCredential()
}

/// Generic-password Keychain storage (no entitlements required for a
/// non-sandboxed app).
final class KeychainBottleMailCredentialStore: BottleMailCredentialStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.birthday.warawarapet.bottlemail",
        account: String = "device-credential"
    ) {
        self.service = service
        self.account = account
    }

    func loadCredential() -> BottleMailCredential? {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(BottleMailCredential.self, from: data)
    }

    func saveCredential(_ credential: BottleMailCredential) throws {
        let data = try JSONEncoder().encode(credential)
        var query = Self.baseQuery(service: service, account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw BottleMailCredentialStoreError.keychain(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw BottleMailCredentialStoreError.keychain(status: updateStatus)
        }
    }

    func clearCredential() {
        let query = Self.baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum BottleMailCredentialStoreError: Error {
    case keychain(status: OSStatus)
}

/// Test stand-in: credential lives in memory only.
final class InMemoryBottleMailCredentialStore: BottleMailCredentialStoring {
    private(set) var credential: BottleMailCredential?

    func loadCredential() -> BottleMailCredential? { credential }
    func saveCredential(_ credential: BottleMailCredential) throws { self.credential = credential }
    func clearCredential() { credential = nil }
}
