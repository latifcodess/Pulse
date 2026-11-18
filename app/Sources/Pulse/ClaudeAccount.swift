import Foundation
import Observation
import PulseCore

/// Les deux façons de récupérer l'usage de Claude, et la session claude.ai.
@MainActor
@Observable
final class ClaudeAccount {
    private(set) var claudeAiConnected = false
    /// Le plan de l'abonnement (« Max », « Pro »…), connu avec Claude Code.
    private(set) var plan: String?

    /// Le Trousseau et le réseau sont bloquants : Task.detached les sort du
    /// thread principal pour ne pas figer l'interface.
    func fetchState(monitor: AiMonitor) async -> AiState {
        switch ClaudeAuthMethod.current {
        case .claudeCode:
            let (state, plan) = await Task.detached(priority: .utility) { Self.fetchWithClaudeCode(monitor) }.value
            self.plan = plan.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return state

        case .claudeAi:
            plan = nil
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

    func connect(sessionKey: String) async {
        claudeAiConnected = await Task.detached { ClaudeSessionKeyStore.save(sessionKey) }.value
    }

    func disconnect() async {
        _ = await Task.detached { ClaudeSessionKeyStore.delete() }.value
        claudeAiConnected = false
    }

    private nonisolated static func fetchWithClaudeCode(_ monitor: AiMonitor) -> (AiState, String?) {
        switch ClaudeCredentials.read() {
        case .token(let token, let plan): (monitor.refreshClaude(accessToken: token), plan)
        case .notConnected: (.notConnected, nil)
        case .expired: (.expired, nil)
        case .unavailable: (.unavailable, nil)
        }
    }
}
