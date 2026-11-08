import Foundation
import Observation
import PulseCore

/// L'état affiché pour un service, actualisé à l'intervalle choisi.
@MainActor
@Observable
final class UsageModel {
    let service: AiService
    let settings: ServiceSettings
    private(set) var state: AiState?
    /// Heure de la dernière réponse valide.
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    private let fetch: @MainActor () async -> AiState
    private var refreshTask: Task<Void, Never>?

    /// `fetch` récupère l'état ; le travail bloquant doit y sortir du thread principal.
    init(service: AiService, fetch: @escaping @MainActor () async -> AiState) {
        self.service = service
        self.settings = ServiceSettings(service: service)
        self.fetch = fetch
        refreshNow()
    }

    /// Suivre ou non ce service. Sans suivi, plus aucune requête n'est faite.
    var isEnabled: Bool {
        get { settings.isEnabled }
        set {
            guard newValue != settings.isEnabled else { return }
            settings.isEnabled = newValue
            if newValue {
                refreshNow()
            } else {
                refreshTask?.cancel()
                refreshTask = nil
                isRefreshing = false
            }
        }
    }

    /// Intervalle entre deux actualisations, en secondes.
    var refreshInterval: Int {
        get { settings.refreshInterval }
        set {
            guard newValue != settings.refreshInterval else { return }
            settings.refreshInterval = newValue
            // Repart sur le nouvel intervalle, sans requête immédiate.
            if settings.isEnabled {
                restart(fetchFirst: false)
            }
        }
    }

    /// Relance une actualisation tout de suite, puis à l'intervalle choisi.
    func refreshNow() {
        guard settings.isEnabled else { return }
        restart(fetchFirst: true)
    }

    private func restart(fetchFirst: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { await refreshLoop(fetchFirst: fetchFirst) }
    }

    private func refreshLoop(fetchFirst: Bool) async {
        if !fetchFirst {
            try? await Task.sleep(for: .seconds(settings.refreshInterval))
        }
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
            try? await Task.sleep(for: .seconds(settings.refreshInterval))
        }
    }

    /// Les limites connues, ou les dernières connues hors ligne.
    var windows: [UsageWindow] {
        switch state {
        case .ok(let usage): usage.windows
        case .offline(let last): last?.windows ?? []
        default: []
        }
    }

    /// Un compte est connecté : l'API a répondu, même sans données exploitables.
    var isSignedIn: Bool {
        switch state {
        case .ok, .offline(.some), .blocked, .unavailable: true
        case nil, .offline(nil), .notConnected, .expired: false
        }
    }

    /// Le texte et la couleur de la puce dans la barre des menus.
    var bar: (text: String, level: UsageLevel) {
        guard !windows.isEmpty else { return (Self.stateText(state), .normal) }
        return Self.barContent(windows: windows, settings: settings)
    }

    /// Ce que la puce affiche pour ces limites. Aussi utilisé par l'aperçu
    /// des réglages.
    static func barContent(windows: [UsageWindow], settings: ServiceSettings) -> (text: String, level: UsageLevel) {
        let shown = settings.display.select(windows)
        let text = shown
            .map { UsageFormat.percent(settings.valueMode.value(forUsed: $0.percent)) }
            .joined(separator: " · ")
        // La couleur suit toujours le % utilisé, même si l'on affiche le restant.
        let highest = shown.map(\.percent).max() ?? 0
        return (text, settings.thresholds.level(for: highest))
    }

    private static func stateText(_ state: AiState?) -> String {
        switch state {
        case nil: "…"
        case .ok, .offline(.some): "indisponible"
        case .offline(nil): "hors ligne"
        case .notConnected: "non connecté"
        case .expired: "expiré"
        case .blocked: "bloqué"
        case .unavailable: "indisponible"
        }
    }
}
