import Foundation
import Observation
import PulseCore

/// Garde l'état affiché et l'actualise toutes les 2 minutes.
@MainActor
@Observable
final class UsageModel {
    private(set) var state: AiState?
    private(set) var claudeAiConnected = false
    private(set) var method = ClaudeAuthMethod.current
    /// Heure de la dernière réponse valide.
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    private let monitor = AiMonitor()
    private var refreshTask: Task<Void, Never>?
    private static let refreshInterval: Duration = .seconds(120)

    init() {
        refreshNow()
    }

    /// Relance une actualisation tout de suite, puis toutes les 2 minutes.
    func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { await refreshLoop() }
    }

    func connectClaudeAi(sessionKey: String) {
        Task {
            claudeAiConnected = await Task.detached { ClaudeSessionKeyStore.save(sessionKey) }.value
            refreshNow()
        }
    }

    func disconnectClaudeAi() {
        Task {
            _ = await Task.detached { ClaudeSessionKeyStore.delete() }.value
            claudeAiConnected = false
            refreshNow()
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            isRefreshing = true
            let newState = await fetchState()
            // Une actualisation plus récente a pu être lancée entre-temps.
            guard !Task.isCancelled else { return }
            state = newState
            isRefreshing = false
            if case .ok = newState {
                lastUpdated = .now
            }
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// Le Trousseau et le réseau sont bloquants : Task.detached les sort du
    /// thread principal pour ne pas figer l'interface.
    private func fetchState() async -> AiState {
        let monitor = monitor
        method = ClaudeAuthMethod.current
        switch method {
        case .claudeCode:
            return await Task.detached(priority: .utility) { Self.fetchWithClaudeCode(monitor) }.value

        case .claudeAi:
            let sessionKey = await Task.detached(priority: .utility) { ClaudeSessionKeyStore.read() }.value
            claudeAiConnected = sessionKey != nil
            guard let sessionKey else { return .notConnected }

            let state = await Task.detached(priority: .utility) {
                monitor.refreshClaudeWeb(sessionKey: sessionKey)
            }.value
            guard state == .blocked, !Task.isCancelled else { return state }
            return await ClaudeWebFallback.fetchState(sessionKey: sessionKey, monitor: monitor)
        }
    }

    private nonisolated static func fetchWithClaudeCode(_ monitor: AiMonitor) -> AiState {
        switch ClaudeCredentials.read() {
        case .token(let token): monitor.refreshClaude(accessToken: token)
        case .notConnected: .notConnected
        case .expired: .expired
        case .unavailable: .unavailable
        }
    }

    /// La fenêtre de session, ou la dernière connue hors ligne.
    private var session: UsageWindow? {
        let usage: AiUsage? =
            switch state {
            case .ok(let usage): usage
            case .offline(let last): last
            default: nil
            }
        return usage?.windows.first(where: { $0.label == "Session (5 h)" })
    }

    /// Le texte affiché dans la barre des menus.
    var sessionText: String {
        if let session {
            return UsageFormat.percent(session.percent)
        }
        switch state {
        case nil: return "…"
        case .ok, .offline(.some): return "indisponible"
        case .offline(nil): return "hors ligne"
        case .notConnected: return "non connecté"
        case .expired: return "expiré"
        case .blocked: return "bloqué"
        case .unavailable: return "indisponible"
        }
    }

    var sessionLevel: UsageLevel {
        session.map { UsageLevel(percent: $0.percent) } ?? .normal
    }
}
