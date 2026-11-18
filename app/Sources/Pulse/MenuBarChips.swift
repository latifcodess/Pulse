import AppKit
import PulseCore
import SwiftUI

// Ce que la barre des menus dessine, pour les trois styles
// (maquette design/pulse-maquettes/MenuBar.dc.html). Les vues sont rendues
// en image (ImageRenderer) pour garder leurs couleurs dans la barre.

/// Une IA telle que la barre des menus l'affiche.
struct BarEntry: Identifiable {
    let kind: ServiceLogo.Kind
    let title: String
    /// « 78% », « 78% · 41% », ou l'état (« non connecté »).
    let text: String
    /// La valeur de l'anneau (utilisé ou restant, selon le réglage de l'IA).
    let ringPercent: Double?
    let level: UsageLevel

    var id: ServiceLogo.Kind { kind }

    @MainActor
    init(_ model: UsageModel) {
        let bar = model.bar
        let shown = model.settings.display.select(model.windows)
        kind = model.service.logoKind
        title = model.service.title
        text = bar.text
        ringPercent = shown.map(\.percent).max().map(model.settings.valueMode.value(forUsed:))
        level = bar.level
    }

    init(kind: ServiceLogo.Kind, title: String, text: String, ringPercent: Double?, level: UsageLevel) {
        self.kind = kind
        self.title = title
        self.text = text
        self.ringPercent = ringPercent
        self.level = level
    }
}

/// Le contenu du style « Compact » : l'IA la plus proche de sa limite.
struct CompactEntry {
    let title: String
    let text: String
    /// L'heure à laquelle la limite sera atteinte, si elle l'est avant le reset.
    let time: String?
    let level: UsageLevel

    @MainActor
    init(_ model: UsageModel, now: Date = .now) {
        let percent = model.highestPercent ?? 0
        title = model.service.title
        text = UsageFormat.percent(model.settings.valueMode.value(forUsed: percent))
        time = model.earliestProjection.map { DetailView.time($0, now: now) }
        level = model.settings.thresholds.level(for: percent)
    }

    init(title: String, text: String, time: String?, level: UsageLevel) {
        self.title = title
        self.text = text
        self.time = time
        self.level = level
    }
}

/// Les couleurs de la barre des menus, claire ou sombre.
struct BarPalette {
    let isDark: Bool

    var foreground: Color { isDark ? PulseTheme.text : .black.opacity(0.85) }
    var secondary: Color { isDark ? PulseTheme.secondary : .black.opacity(0.5) }
    /// Le fond de l'élément regroupé : blanc à 10 %.
    var capsule: Color { isDark ? .white.opacity(0.10) : .black.opacity(0.07) }
    var ringTrack: Color { isDark ? .white.opacity(0.18) : .black.opacity(0.15) }

    /// Orange ou rouge au-delà des seuils, sinon `normal`.
    func color(_ level: UsageLevel, normal: Color) -> Color {
        switch level {
        case .normal: normal
        case .warning: PulseTheme.warning
        case .critical: PulseTheme.critical
        }
    }
}

// MARK: - Éléments

/// Style A : la pastille du logo et le %.
struct LogoPercentEntryView: View {
    let entry: BarEntry
    let palette: BarPalette

    var body: some View {
        HStack(spacing: 4) {
            LogoBadge(kind: entry.kind, size: 12, onLightBackground: !palette.isDark)
            Text(entry.text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.color(entry.level, normal: palette.foreground))
        }
    }
}

/// Style B : un anneau de 16 pt, bleu, orange ou rouge.
struct RingEntryView: View {
    let entry: BarEntry
    let palette: BarPalette

    var body: some View {
        UsageRing(
            percent: entry.ringPercent ?? 0,
            color: palette.color(entry.level, normal: PulseTheme.accent),
            size: 16,
            trackColor: palette.ringTrack)
    }
}

/// Style C : le pouls de Pulse, le % et l'heure prévue.
struct CompactEntryView: View {
    let entry: CompactEntry
    let palette: BarPalette

    var body: some View {
        let color = palette.color(entry.level, normal: palette.foreground)
        HStack(spacing: 5) {
            PulseGlyph()
                .stroke(color, style: StrokeStyle(lineWidth: 2.4 * 14 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
            Text(entry.text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(color)
            if let time = entry.time {
                Text("· \(time)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            }
        }
    }
}

// MARK: - Contenu d'un élément de la barre

/// Ce que dessine un élément de la barre des menus.
enum BarContent {
    /// Une seule IA, style A ou B.
    case single(BarEntry, MenuBarStyle)
    /// Toutes les IA affichées, regroupées, style A ou B.
    case group([BarEntry], MenuBarStyle)
    /// Style C.
    case compact(CompactEntry)
}

/// Un élément de la barre : seul, ou dans une capsule de 22 pt (5 pt de
/// coins, blanc à 10 %) quand il regroupe les IA.
struct BarContentView: View {
    let content: BarContent
    let palette: BarPalette

    var body: some View {
        switch content {
        case .single(let entry, let style):
            entryView(entry, style)
                .padding(.horizontal, 2)
                .frame(height: 22)
        case .group(let entries, let style):
            capsule(spacing: style == .rings ? 8 : 12) {
                ForEach(entries) { entryView($0, style) }
            }
        case .compact(let entry):
            capsule(spacing: 0) {
                CompactEntryView(entry: entry, palette: palette)
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: BarEntry, _ style: MenuBarStyle) -> some View {
        if style == .rings {
            RingEntryView(entry: entry, palette: palette)
        } else {
            LogoPercentEntryView(entry: entry, palette: palette)
        }
    }

    private func capsule(spacing: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: spacing, content: content)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(palette.capsule, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    /// L'infobulle et le texte lu par VoiceOver.
    var description: String {
        switch content {
        case .single(let entry, _): "\(entry.title) : \(entry.text)"
        case .group(let entries, _): entries.map { "\($0.title) : \($0.text)" }.joined(separator: " · ")
        case .compact(let entry):
            "\(entry.title) : \(entry.text)" + (entry.time.map { " · limite vers \($0)" } ?? "")
        }
    }

    /// L'image à mettre dans le bouton de la barre.
    @MainActor
    func image() -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        // Une image « template » serait affichée en monochrome.
        image?.isTemplate = false
        return image
    }
}
