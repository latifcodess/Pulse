import Foundation
import Security

/// Le cookie sessionKey de claude.ai, rangé dans le Trousseau sous le nom de Pulse.
enum ClaudeSessionKeyStore {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ch.latifcodess.pulse",
            kSecAttrAccount as String: "claude.ai-sessionKey",
        ]
    }

    static func read() -> String? {
        var search = query
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        search[kSecReturnData as String] = true

        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let sessionKey = String(data: data, encoding: .utf8),
            !sessionKey.isEmpty
        else {
            return nil
        }
        return sessionKey
    }

    /// Remplace la valeur si elle existe déjà, sinon la crée.
    static func save(_ sessionKey: String) -> Bool {
        let data = Data(sessionKey.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
