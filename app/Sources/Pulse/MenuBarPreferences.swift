import Foundation
import Observation

/// Les trois façons d'afficher les IA dans la barre des menus
/// (maquette design/pulse-maquettes/MenuBar.dc.html).
enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// Le logo et le % de chaque IA.
    case logoPercent
    /// Un mini anneau par IA.
    case rings
    /// Seulement l'IA la plus proche de sa limite, et l'heure prévue.
    case compact

    var id: Self { self }

    var title: String {
        switch self {
        case .logoPercent: "Logo + %"
        case .rings: "Anneaux"
        case .compact: "Compact"
        }
    }

    var subtitle: String {
        switch self {
        case .logoPercent: "Toutes les IA, lisible d'un coup d'œil."
        case .rings: "Le plus compact, idéal avec une encoche."
        case .compact: "Seulement l'IA la plus proche de sa limite ; un clic ouvre sa fenêtre."
        }
    }
}

/// Les préférences de la barre des menus, communes à toutes les IA, rangées
/// dans UserDefaults (ce ne sont pas des secrets).
@MainActor
@Observable
final class MenuBarPreferences {
    /// Seuils proposés pour masquer une IA ; 0 : jamais.
    static let hideOptions = [0, 25, 50, 75]

    @ObservationIgnored private let defaults: UserDefaults

    var style: MenuBarStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }
    /// Toutes les IA dans un seul élément, ou une icône par IA.
    var groupsServices: Bool {
        didSet { defaults.set(groupsServices, forKey: Keys.groups) }
    }
    /// Une IA reste masquée tant que sa limite la plus proche est sous ce %.
    /// 0 : toujours affichée.
    var hideBelow: Int {
        didSet { defaults.set(hideBelow, forKey: Keys.hideBelow) }
    }

    private enum Keys {
        static let style = "menuBar.style"
        static let groups = "menuBar.groupsServices"
        static let hideBelow = "menuBar.hideBelow"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Une valeur absente ou invalide donne la valeur par défaut.
        style = defaults.string(forKey: Keys.style).flatMap(MenuBarStyle.init(rawValue:)) ?? .logoPercent
        groupsServices = defaults.object(forKey: Keys.groups) as? Bool ?? true
        let hide = defaults.object(forKey: Keys.hideBelow) as? Int ?? 0
        hideBelow = Self.hideOptions.contains(hide) ? hide : 0
    }

    /// L'IA a sa place dans la barre : suivie, et pas sous le seuil de masquage.
    /// Sans valeur connue (non connectée, erreur), elle reste affichée.
    func showsInBar(_ model: UsageModel) -> Bool {
        guard model.isEnabled else { return false }
        guard hideBelow > 0, let highest = model.highestPercent else { return true }
        return highest >= Double(hideBelow)
    }
}
