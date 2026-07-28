import Foundation
import Security

/// Persists entitlement state for fail-open offline behavior and legacy-user detection.
enum EntitlementCache {
    private static let accessStateKey = "dreft.entitlement.accessState"
    private static let lastVerifiedKey = "dreft.entitlement.lastVerified"
    private static let everSubscribedKey = "dreft.entitlement.everSubscribed"
    private static let legacyUserKey = "dreft.entitlement.legacyUser"
    private static let keychainLegacyKey = "com.aiflowhustle.dreft.legacyUser"

    struct Snapshot: Codable {
        var accessState: DreftAccessState
        var lastVerified: Date
    }

    static var isLegacyUser: Bool {
        if UserDefaults.standard.bool(forKey: legacyUserKey) { return true }
        return readLegacyFromKeychain()
    }

    static var hasEverSubscribed: Bool {
        UserDefaults.standard.bool(forKey: everSubscribedKey)
    }

    static func markEverSubscribed() {
        UserDefaults.standard.set(true, forKey: everSubscribedKey)
    }

    static func persistLegacyUser(_ isLegacy: Bool) {
        UserDefaults.standard.set(isLegacy, forKey: legacyUserKey)
        if isLegacy {
            writeLegacyToKeychain(true)
        }
    }

    static func save(_ accessState: DreftAccessState) {
        UserDefaults.standard.set(accessState.rawValue, forKey: accessStateKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastVerifiedKey)
    }

    static func load() -> Snapshot? {
        guard let raw = UserDefaults.standard.string(forKey: accessStateKey),
              let state = DreftAccessState(rawValue: raw) else { return nil }
        let timestamp = UserDefaults.standard.double(forKey: lastVerifiedKey)
        let date = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .distantPast
        return Snapshot(accessState: state, lastVerified: date)
    }

    /// Preserve last known full access when StoreKit is unreachable.
    static func shouldFailOpen(_ snapshot: Snapshot) -> Bool {
        guard snapshot.accessState == .fullAccess else { return false }
        return Date().timeIntervalSince(snapshot.lastVerified) < 60 * 60 * 24 * 7
    }

    private static func readLegacyFromKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainLegacyKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return false }
        return value == "1"
    }

    private static func writeLegacyToKeychain(_ isLegacy: Bool) {
        let data = Data((isLegacy ? "1" : "0").utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainLegacyKey,
        ]
        SecItemDelete(query as CFDictionary)
        guard isLegacy else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
