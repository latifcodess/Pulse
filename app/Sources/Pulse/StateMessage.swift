import PulseCore

/// Le message affiché quand une IA n'a pas de données à jour.
enum StateMessage {
    @MainActor
    static func message(for state: AiState?, service: AiService, refreshInterval: Int) -> (text: String, icon: String)? {
        switch state {
        case nil: ("Chargement…", "hourglass")
        case .ok: nil
        case .offline(.some): ("Hors ligne : dernières valeurs connues.", "wifi.slash")
        case .offline(nil): ("Hors ligne.", "wifi.slash")
        case .notConnected: (service.notConnectedHint, "person.crop.circle.badge.questionmark")
        case .expired: (service.expiredHint, "clock.badge.exclamationmark")
        case .blocked: ("Accès temporairement bloqué. Nouvel essai dans \(UsageFormat.interval(refreshInterval)).", "hand.raised")
        case .unavailable: ("Données indisponibles.", "exclamationmark.triangle")
        }
    }

    /// Le mot court de l'en-tête : « Connecté », « Non connecté »…
    static func status(_ state: AiState?) -> String {
        switch state {
        case nil: "Chargement…"
        case .ok, .offline(.some): "Connecté"
        case .offline(nil): "Hors ligne"
        case .notConnected: "Non connecté"
        case .expired: "Connexion expirée"
        case .blocked: "Accès bloqué"
        case .unavailable: "Données indisponibles"
        }
    }
}
