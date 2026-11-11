import AppKit
import PulseCore
import SwiftUI

/// Ce que l'interface affiche pour chaque service.
extension AiService {
    var title: String {
        switch self {
        case .claude: "Claude"
        case .chatGpt: "ChatGPT"
        case .gemini: "Gemini"
        case .copilot: "Copilot"
        }
    }

    /// Le logo, en image « template » colorée par le système ou par SwiftUI.
    func logo(size: CGFloat = 16) -> NSImage {
        switch self {
        case .claude: ServiceLogo.image(.claude, size: size)
        case .chatGpt: ServiceLogo.image(.chatGpt, size: size)
        case .gemini: ServiceLogo.image(.gemini, size: size)
        case .copilot: ServiceLogo.image(.copilot, size: size)
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
        case .copilot: "GitHub CLI n'est pas connecté. Installez gh, puis lancez « gh auth login » dans le Terminal."
        case .gemini: "Gemini CLI n'est pas connecté. Lancez « gemini » dans le Terminal et connectez-vous avec Google."
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
        case .copilot: "Le token de GitHub CLI n'est plus accepté. Lancez « gh auth login » dans le Terminal."
        case .gemini: "La connexion de Gemini CLI n'est plus acceptée. Relancez « gemini » pour vous reconnecter."
        }
    }
}
