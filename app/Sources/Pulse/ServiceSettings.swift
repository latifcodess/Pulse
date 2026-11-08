import Foundation
import Observation
import PulseCore

/// Quelle(s) limite(s) la puce affiche.
enum BarDisplay: String, CaseIterable, Identifiable {
    case first
    case second
    case both

    var id: Self { self }

    var title: String {
        switch self {
        case .first: "1re limite"
        case .second: "2e limite"
        case .both: "Les deux"
        }
    }

    /// Les limites à afficher. Sans 2e limite, on se rabat sur la 1re.
    func select(_ windows: [UsageWindow]) -> [UsageWindow] {
        switch self {
        case .first: Array(windows.prefix(1))
        case .second: windows.count > 1 ? [windows[1]] : Array(windows.prefix(1))
        case .both: Array(windows.prefix(2))
        }
    }
}

/// Afficher le % utilisé ou le % restant.
enum ValueMode: String, CaseIterable, Identifiable {
    case used
    case remaining

    var id: Self { self }

    var title: String {
        switch self {
        case .used: "Utilisé"
        case .remaining: "Restant"
        }
    }

    func value(forUsed percent: Double) -> Double {
        switch self {
        case .used: percent
        case .remaining: 100 - percent
        }
    }
}

/// Les seuils d'alerte, en % utilisé.
struct Thresholds: Equatable {
    var warning: Int
    var critical: Int

    static let standard = Thresholds(warning: 75, critical: 90)

    func level(for percent: Double) -> UsageLevel {
        if percent > Double(critical) {
            .critical
        } else if percent > Double(warning) {
            .warning
        } else {
            .normal
        }
    }
}

/// Les préférences d'une IA, rangées dans UserDefaults (ce ne sont pas des
/// secrets). Chaque modification est enregistrée tout de suite.
@MainActor
@Observable
final class ServiceSettings {
    /// Intervalles proposés, en secondes.
    static let intervals = [30, 60, 120, 300, 600]
    static let defaultInterval = 120

    let service: AiService
    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: key("enabled")) }
    }
    var display: BarDisplay {
        didSet { defaults.set(display.rawValue, forKey: key("display")) }
    }
    var valueMode: ValueMode {
        didSet { defaults.set(valueMode.rawValue, forKey: key("valueMode")) }
    }
    /// En secondes, entre 30 s et 10 min.
    var refreshInterval: Int {
        didSet { defaults.set(refreshInterval, forKey: key("refreshInterval")) }
    }
    var thresholds: Thresholds {
        didSet {
            defaults.set(thresholds.warning, forKey: key("warningThreshold"))
            defaults.set(thresholds.critical, forKey: key("criticalThreshold"))
        }
    }

    init(service: AiService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        let storedKey = { (name: String) in "\(service.storageKey).\(name)" }

        // Une valeur absente ou invalide donne la valeur par défaut.
        isEnabled = defaults.object(forKey: storedKey("enabled")) as? Bool ?? true
        display = defaults.string(forKey: storedKey("display")).flatMap(BarDisplay.init(rawValue:)) ?? .first
        valueMode = defaults.string(forKey: storedKey("valueMode")).flatMap(ValueMode.init(rawValue:)) ?? .used
        let interval = defaults.object(forKey: storedKey("refreshInterval")) as? Int ?? Self.defaultInterval
        refreshInterval = min(max(interval, 30), 600)

        let warning = defaults.object(forKey: storedKey("warningThreshold")) as? Int ?? Thresholds.standard.warning
        let critical = defaults.object(forKey: storedKey("criticalThreshold")) as? Int ?? Thresholds.standard.critical
        // Mêmes règles que dans les réglages : 5 points d'écart au moins.
        let valid = warning >= 5 && critical <= 100 && critical - warning >= 5
        thresholds = valid ? Thresholds(warning: warning, critical: critical) : .standard
    }

    private func key(_ name: String) -> String {
        "\(service.storageKey).\(name)"
    }
}

extension AiService {
    /// Préfixe des clés de préférences.
    var storageKey: String {
        switch self {
        case .claude: "claude"
        case .chatGpt: "chatgpt"
        case .gemini: "gemini"
        case .copilot: "copilot"
        }
    }
}
