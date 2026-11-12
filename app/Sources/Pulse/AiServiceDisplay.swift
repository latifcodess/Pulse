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

    @MainActor
    var notConnectedHint: String {
        if self != .claude, ConnectionMethod.current(for: self) == .account {
            return "Non connecté. Connectez votre \(accountName) dans les Réglages."
        }
        switch self {
        case .claude: return "Non connecté. Choisissez une méthode de connexion dans les Réglages."
        case .chatGpt: return "Codex n'est pas connecté. Lancez « codex login » dans le Terminal, ou connectez votre compte dans les Réglages."
        case .copilot: return "GitHub CLI n'est pas connecté. Lancez « gh auth login » dans le Terminal, ou connectez votre compte dans les Réglages."
        case .gemini: return "Gemini CLI n'est pas connecté. Lancez « gemini » dans le Terminal, ou connectez votre compte dans les Réglages."
        }
    }

    @MainActor
    var expiredHint: String {
        if self != .claude, ConnectionMethod.current(for: self) == .account {
            return "La connexion a expiré. Reconnectez votre \(accountName) dans les Réglages."
        }
        switch self {
        case .claude:
            switch ClaudeAuthMethod.current {
            case .claudeCode: return "Le token de Claude Code a expiré. Lancez Claude Code pour le renouveler."
            case .claudeAi: return "La session claude.ai a expiré. Reconnectez-vous dans les Réglages."
            }
        case .chatGpt: return "Le token de Codex a expiré. Lancez Codex pour le renouveler."
        case .copilot: return "Le token de GitHub CLI n'est plus accepté. Lancez « gh auth login » dans le Terminal."
        case .gemini: return "La connexion de Gemini CLI n'est plus acceptée. Relancez « gemini » pour vous reconnecter."
        }
    }
}
