import PulseCore
import SwiftUI

/// Ce que l'interface affiche pour chaque service. Les icônes sont des symboles
/// système, pas les logos officiels.
extension AiService {
    var title: String {
        switch self {
        case .claude: "Claude"
        case .chatGpt: "ChatGPT"
        case .gemini: "Gemini"
        case .copilot: "Copilot"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .chatGpt: "hexagon"
        case .gemini: "diamond"
        case .copilot: "airplane"
        }
    }

    var tint: Color {
        switch self {
        case .claude: .orange
        case .chatGpt: .green
        case .gemini: .blue
        case .copilot: .purple
        }
    }

    var notConnectedHint: String {
        switch self {
        case .claude: "Non connecté. Choisissez une méthode de connexion dans les Réglages."
        case .chatGpt: "Codex n'est pas connecté. Lancez « codex login » dans le Terminal."
        case .gemini, .copilot: "Non connecté."
        }
    }

    @MainActor
    var expiredHint: String {
        switch self {
        case .claude:
            switch ClaudeAuthMethod.current {
            case .claudeCode: "Le token de Claude Code a expiré. Lancez Claude Code pour le renouveler."
            case .claudeAi: "La session claude.ai a expiré. Reconnectez-vous dans les Réglages."
            }
        case .chatGpt: "Le token de Codex a expiré. Lancez Codex pour le renouveler."
        case .gemini, .copilot: "La connexion a expiré."
        }
    }
}
