import Foundation
import Observation
import PulseCore

/// L'état affiché pour un service, actualisé toutes les 2 minutes.
@MainActor
@Observable
final class UsageModel {
    let service: AiService
    private(set) var state: AiState?
    /// Heure de la dernière réponse valide.
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    private let fetch: @MainActor () async -> AiState
    private var refreshTask: Task<Void, Never>?
    private static let refreshInterval: Duration = .seconds(120)

    /// `fetch` récupère l'état ; le travail bloquant doit y sortir du thread principal.
    init(service: AiService, fetch: @escaping @MainActor () async -> AiState) {
        self.service = service
        self.fetch = fetch
        refreshNow()
    }

    /// Relance une actualisation tout de suite, puis toutes les 2 minutes.
    func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { await refreshLoop() }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            isRefreshing = true
            let newState = await fetch()
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

    /// La première limite (la session), ou la dernière connue hors ligne.
    private var session: UsageWindow? {
        switch state {
        case .ok(let usage): usage.windows.first
        case .offline(let last): last?.windows.first
        default: nil
        }
    }

    /// Le texte affiché dans la barre des menus.
    var barText: String {
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

    var barLevel: UsageLevel {
        session.map { UsageLevel(percent: $0.percent) } ?? .normal
    }
}
