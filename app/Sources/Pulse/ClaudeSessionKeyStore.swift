import Foundation

/// Le cookie sessionKey de claude.ai, rangé dans le Trousseau sous le nom de Pulse.
enum ClaudeSessionKeyStore {
    static func read() -> String? {
        KeychainSecret.claudeSession.read()
    }

    static func save(_ sessionKey: String) -> Bool {
        KeychainSecret.claudeSession.save(sessionKey)
    }

    static func delete() -> Bool {
        KeychainSecret.claudeSession.delete()
    }
}
