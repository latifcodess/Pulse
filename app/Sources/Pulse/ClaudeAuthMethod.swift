import Foundation

/// La méthode de connexion choisie pour Claude. Ce choix n'est pas un secret :
/// il est rangé dans les préférences.
enum ClaudeAuthMethod: String, CaseIterable, Identifiable {
    case claudeCode
    case claudeAi

    static let storageKey = "claudeAuthMethod"

    static var current: ClaudeAuthMethod {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .claudeCode
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeAi: "Compte claude.ai"
        }
    }
}
