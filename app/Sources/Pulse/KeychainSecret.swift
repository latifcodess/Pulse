import Foundation
import Security

/// Un secret de Pulse dans le Trousseau (service « ch.latifcodess.pulse »).
/// Jamais dans UserDefaults ni dans un fichier.
struct KeychainSecret: Sendable {
    let account: String

    static let claudeSession = KeychainSecret(account: "claude.ai-sessionKey")
    static let chatGptSession = KeychainSecret(account: "chatgpt.com-session")
    static let googleRefreshToken = KeychainSecret(account: "google-refreshToken")
    static let githubToken = KeychainSecret(account: "github-token")

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ch.latifcodess.pulse",
            kSecAttrAccount as String: account,
        ]
    }

    /// Appel bloquant (le Trousseau peut demander une autorisation) : à faire
    /// hors du thread principal.
    func read() -> String? {
        var search = query
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        search[kSecReturnData as String] = true

        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    /// Remplace la valeur si elle existe déjà, sinon la crée.
    func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
