import SwiftUI

/// Les couleurs et dimensions de Pulse, reprises des maquettes
/// (design/pulse-maquettes). Thème sombre uniquement.
enum PulseTheme {
    // Fonds
    static let background = Color(hex: 0x1C1C1E)
    static let sidebar = Color(hex: 0x252527)
    static let settingsBackground = Color(hex: 0x1E1E20)
    /// Cartes et sections : blanc à 4 %, bordure blanche à 6 %.
    static let card = Color.white.opacity(0.04)
    static let cardBorder = Color.white.opacity(0.06)
    /// Bordure des fenêtres : blanc à 8 %.
    static let border = Color.white.opacity(0.08)
    static let cornerRadius: CGFloat = 14

    // Textes
    static let text = Color(hex: 0xF5F5F7)
    static let secondary = Color(hex: 0xA1A1A6)
    static let tertiary = Color(hex: 0x8E8E93)

    // Niveaux
    static let accent = Color(hex: 0x64D2FF)
    /// Textes, barres et anneaux sous le seuil orange : la couleur choisie
    /// dans les réglages (voir NormalColor).
    static var normal: Color { Color(hex: NormalColor.shared.hex) }
    static let warning = Color(hex: 0xFF9F0A)
    static let critical = Color(hex: 0xFF453A)
    /// Textes sur fond orange ou rouge.
    static let warningText = Color(hex: 0xFFB340)
    static let warningSoftText = Color(hex: 0xFFD08A)
    static let criticalText = Color(hex: 0xFF6961)

    // États
    static let connected = Color(hex: 0x30D158)
    static let disconnected = Color(hex: 0x8E8E93)

    // Contrôles
    static let controlFill = Color.white.opacity(0.08)
    static let segmentTrack = Color.white.opacity(0.06)
    static let segmentSelected = Color(hex: 0x48484A)
    static let popupFill = Color(hex: 0x3A3A3C)

    /// Accent, orange (≥ seuil orange) ou rouge (≥ seuil rouge).
    static func levelColor(_ percent: Double, warning: Int, critical: Int) -> Color {
        if percent >= Double(critical) { return Self.critical }
        if percent >= Double(warning) { return Self.warning }
        return normal
    }
}

/// La couleur des pourcentages, barres et anneaux sous le seuil orange.
/// L'app la règle (Réglages › Général) ; le widget la lit dans son fichier.
/// Observable : les vues qui l'affichent se redessinent quand elle change.
@Observable
final class NormalColor: @unchecked Sendable {
    static let shared = NormalColor()
    static let defaultHex: UInt32 = 0x64D2FF

    /// Les couleurs proposées dans les réglages.
    static let presets: [(name: String, hex: UInt32)] = [
        ("Bleu ciel", 0x64D2FF), ("Blanc", 0xF5F5F7), ("Vert", 0x30D158),
        ("Menthe", 0x66D4CF), ("Indigo", 0x7D7AFF), ("Gris clair", 0xAEAEB2),
        ("Vert sauge", 0x8FD19E), ("Citron vert", 0xB5E853), ("Turquoise", 0x40C8E0),
        ("Bleu pervenche", 0x8AB4F8), ("Glacier", 0xA5E4F0), ("Rose", 0xFF7AB6),
    ]

    var hex: UInt32 = defaultHex
}

extension Color {
    /// Une couleur à partir de son code hexadécimal, par ex. 0x1C1C1E.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

extension ServiceLogo.Kind {
    /// La couleur de l'IA, utilisée en fond teinté derrière son logo.
    var tint: Color {
        switch self {
        case .claude: Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
        case .chatGpt: .white
        case .gemini: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255)
        case .copilot: Color(red: 191 / 255, green: 90 / 255, blue: 242 / 255)
        }
    }

    /// La couleur du logo sur fond clair : la couleur de l'IA, ou du noir.
    var inkOnLight: Color {
        self == .chatGpt ? .black.opacity(0.85) : tint
    }

    /// La couleur du logo sur ce fond teinté.
    var ink: Color {
        switch self {
        case .claude: Color(hex: 0xF0A487)
        case .chatGpt: Color(hex: 0xE5E5EA)
        case .gemini: Color(hex: 0xB4B3FF)
        case .copilot: Color(hex: 0xDDA6F7)
        }
    }
}

extension View {
    /// Chiffres à largeur fixe, et transition douce quand la valeur change.
    func animatedNumber(_ value: Double) -> some View {
        monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(.smooth(duration: 0.4), value: value)
    }
}
