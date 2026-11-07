import Observation
import PulseCore

/// Garde l'état affiché et l'actualise toutes les 2 minutes.
@MainActor
@Observable
final class UsageModel {
    private(set) var state: AiState?

    private let monitor = AiMonitor()
    private static let refreshInterval: Duration = .seconds(120)

    init() {
        Task { await refreshLoop() }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            let monitor = monitor
            // Task.detached quitte le thread principal : le Trousseau et le réseau
            // sont bloquants et ne doivent pas figer l'interface.
            state = await Task.detached(priority: .utility) {
                Self.fetchState(monitor)
            }.value
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    private nonisolated static func fetchState(_ monitor: AiMonitor) -> AiState {
        switch ClaudeCredentials.read() {
        case .token(let token): monitor.refreshClaude(accessToken: token)
        case .notConnected: .notConnected
        case .expired: .expired
        case .unavailable: .unavailable
        }
    }

    /// Le texte affiché dans la barre des menus.
    var sessionText: String {
        switch state {
        case nil: "…"
        case .ok(let usage): Self.sessionText(usage)
        case .offline(let last?): Self.sessionText(last)
        case .offline(nil): "hors ligne"
        case .notConnected: "non connecté"
        case .expired: "expiré"
        case .blocked: "bloqué"
        case .unavailable: "indisponible"
        }
    }

    private static func sessionText(_ usage: AiUsage) -> String {
        guard let session = usage.windows.first(where: { $0.label == "Session (5 h)" }) else {
            return "indisponible"
        }
        return "\(Int(session.percent.rounded())) %"
    }
}
