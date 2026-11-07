import Foundation
import Security

/// Lit le token de Claude Code dans le Trousseau, en lecture seule. Il est relu
/// à chaque actualisation et jamais conservé : c'est Claude Code qui le renouvelle.
enum ClaudeCredentials {
    enum Result {
        case token(String)
        case notConnected
        case expired
        case unavailable
    }

    private static let service = "Claude Code-credentials"

    static func read() -> Result {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .unavailable }
            return parse(data)
        case errSecItemNotFound, errSecUserCanceled, errSecAuthFailed:
            return .notConnected
        default:
            return .unavailable
        }
    }

    private static func parse(_ data: Data) -> Result {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            return .unavailable
        }

        // Sans expiresAt lisible, on tente quand même : l'API tranchera.
        if let expiresAt = oauth["expiresAt"] as? Double, isPast(expiresAt) {
            return .expired
        }
        return .token(token)
    }

    /// expiresAt est en millisecondes ; une valeur plus petite est lue en secondes.
    private static func isPast(_ expiresAt: Double) -> Bool {
        let seconds = expiresAt > 100_000_000_000 ? expiresAt / 1000 : expiresAt
        return seconds <= Date.now.timeIntervalSince1970
    }
}
