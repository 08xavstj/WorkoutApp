import Foundation
import Security

/// Small secrets (the Oura sign-in) in the iOS Keychain, on this device only.
/// Readable after the first unlock, so a background refresh can sync while
/// the phone is locked.
nonisolated enum KeychainStore {
    private static let service = "com.lontraindustries.workoutapp"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// A read that failed for a reason other than "no such item" (the phone
    /// not yet unlocked since a restart, or a passing Keychain error): the
    /// item may well be there, so it must not be taken as signed out.
    nonisolated struct ReadError: LocalizedError {
        var status: OSStatus
        var errorDescription: String? { "Keychain error \(status)." }
    }

    /// The item's data; nil only when there is no such item.
    static func data(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw ReadError(status: status)
        }
    }

    @discardableResult
    static func set(_ data: Data?, for account: String) -> Bool {
        guard let data else {
            let status = SecItemDelete(query(account) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(query(account).merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func string(_ account: String) throws -> String? {
        try data(account).map { String(decoding: $0, as: UTF8.self) }
    }

    @discardableResult
    static func set(_ string: String?, for account: String) -> Bool {
        set(string.map { Data($0.utf8) }, for: account)
    }

    /// Nil when there is no such item or it doesn't decode; throws `ReadError` when it couldn't be read.
    static func value<Value: Decodable>(_ type: Value.Type, _ account: String) throws -> Value? {
        try data(account).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    @discardableResult
    static func set<Value: Encodable>(value: Value?, for account: String) -> Bool {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: account)
    }
}
