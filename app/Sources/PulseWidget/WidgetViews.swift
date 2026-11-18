import AppKit
import SwiftUI
import WidgetKit

// Les widgets de Pulse (maquette design/pulse-maquettes/Widgets.dc.html),
// faits avec les composants partagés de l'app (Shared/UI).

// MARK: - Petit et grand : une IA

struct SingleServiceView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let service = entry.service, service.followed {
                if family == .systemLarge {
                    LargeServiceView(service: service, now: entry.date)
                } else {
                    SmallServiceView(service: service, now: entry.date)
                }
            } else {
                NoDataView(serviceID: entry.serviceID, notFollowed: entry.service?.followed == false)
            }
        }
        // Un clic ouvre la fenêtre de l'IA dans la barre des menus.
        .widgetURL(entry.serviceID.map(PulseLink.url(serviceID:)))
    }
}

/// Petit : anneau, %, et la projection ou le reset.
struct SmallServiceView: View {
    let service: WidgetSnapshot.Service
    let now: Date

    var body: some View {
        let stale = service.isStale(at: now)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                LogoBadge(kind: service.logoKind, size: 14)
                Text(service.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)

            if let window = service.nearestWindow {
                HStack(spacing: 12) {
                    ZStack {
                        UsageRing.widget(percent: window.percent, color: WidgetFormat.color(window.percent, service, stale: stale))
                        Text(UsageFormatShort.percent(window.percent))
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(stale ? PulseTheme.tertiary : PulseTheme.text)
                    }
                    .frame(width: 64, height: 64)
                    let lines = WidgetFormat.labelLines(window.label)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lines.0)
                        if let second = lines.1 { Text(second) }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(stale ? PulseTheme.tertiary : PulseTheme.secondary)
                }
                Spacer(minLength: 6)

                if stale {
                    StaleFootnote(updatedAt: service.updatedAt, now: now)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        if let fullAt = window.projectedFullAt {
                            Text("Limite vers \(ChartFormat.time(fullAt, now: now))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PulseTheme.warningText)
                        }
                        if let resetsAt = window.resetsAt {
                            Text(WidgetFormat.reset(resetsAt, now: now))
                                .font(.system(size: 11))
                                .foregroundStyle(PulseTheme.secondary)
                        }
                    }
                    .monospacedDigit()
                }
            } else {
                StateMessage(service: service)
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }
}

/// Grand : gros %, graphique avec la projection en pointillés, puis les limites.
struct LargeServiceView: View {
    let service: WidgetSnapshot.Service
    let now: Date

    var body: some View {
        let stale = service.isStale(at: now)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    LogoBadge(kind: service.logoKind, size: 16)
                    Text(service.title)
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                Text(WidgetFormat.updated(service.updatedAt, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(stale ? PulseTheme.warningText : PulseTheme.secondary)
            }

            if let nearest = service.nearestWindow {
                let color = WidgetFormat.color(nearest.percent, service, stale: stale)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(UsageFormatShort.percent(nearest.percent))
                        .font(.system(size: 32, weight: .bold))
                        .kerning(-1)
                        .monospacedDigit()
                        .foregroundStyle(color)
                    Text(WidgetFormat.limitPhrase(nearest.label))
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.secondary)
                }

                // Le % date de la dernière mesure : le graphique part de là.
                ProjectionChart(
                    samples: (nearest.history ?? []).map { ChartSample(date: $0.date, percent: $0.percent) },
                    now: service.updatedAt ?? now,
                    percent: nearest.percent,
                    resetsAt: nearest.resetsAt,
                    projectedFullAt: stale ? nil : nearest.projectedFullAt,
                    color: color,
                    height: 110,
                    compact: true)

                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    ForEach(Array(service.windows.prefix(3).enumerated()), id: \.offset) { _, window in
                        LargeLimitRow(
                            window: window, isNearest: window.label == nearest.label,
                            service: service, stale: stale, now: now)
                    }
                }
            } else {
                StateMessage(service: service)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }
}

/// « Session (5 h) · Limite vers 15:32 », ou « Semaine · 41% · Reset lun. 09:00 ».
private struct LargeLimitRow: View {
    let window: WidgetSnapshot.Window
    let isNearest: Bool
    let service: WidgetSnapshot.Service
    let stale: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(isNearest ? window.label : "\(window.label) · \(UsageFormatShort.percent(window.percent))")
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                if let fullAt = window.projectedFullAt, !stale {
                    Text("Limite vers \(ChartFormat.time(fullAt, now: now))")
                        .foregroundStyle(PulseTheme.warningText)
                } else if let resetsAt = window.resetsAt {
                    Text(WidgetFormat.reset(resetsAt, now: now))
                        .foregroundStyle(PulseTheme.secondary)
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .lineLimit(1)
            LimitBar(percent: window.percent, color: WidgetFormat.color(window.percent, service, stale: stale), height: 5)
        }
    }
}

// MARK: - Moyen : les 4 IA

struct AllServicesView: View {
    let entry: PulseEntry

    var body: some View {
        if let services = entry.snapshot?.services, !services.isEmpty {
            VStack(spacing: 9) {
                ForEach(services.prefix(4)) { service in
                    // Chaque ligne ouvre la fenêtre de son IA.
                    Link(destination: PulseLink.url(serviceID: service.id)) {
                        MediumRow(service: service, now: entry.date)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        } else {
            NoDataView(serviceID: nil, notFollowed: false)
        }
    }
}

/// Logo, nom, projection ou reset, barre et %.
struct MediumRow: View {
    let service: WidgetSnapshot.Service
    let now: Date

    var body: some View {
        let stale = service.followed && service.isStale(at: now)
        let window = service.followed ? service.nearestWindow : nil
        let color = window.map { WidgetFormat.color($0.percent, service, stale: stale) } ?? PulseTheme.disconnected
        HStack(spacing: 10) {
            LogoBadge(kind: service.logoKind, size: 16)
                .opacity(service.followed ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(service.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(service.followed ? PulseTheme.text : PulseTheme.tertiary)
                    Spacer(minLength: 6)
                    subtitle(window: window, stale: stale)
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
                LimitBar(percent: window?.percent ?? 0, color: color, height: 5)
            }
            Text(window.map { UsageFormatShort.percent($0.percent) } ?? "—")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(window == nil ? PulseTheme.tertiary : color)
                .frame(width: 36, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func subtitle(window: WidgetSnapshot.Window?, stale: Bool) -> some View {
        if !service.followed {
            Text("Non suivie").foregroundStyle(PulseTheme.tertiary)
        } else if let window {
            if stale {
                Text(WidgetFormat.updated(service.updatedAt, now: now)).foregroundStyle(PulseTheme.secondary)
            } else if let fullAt = window.projectedFullAt {
                Text("Limite vers \(ChartFormat.time(fullAt, now: now))").foregroundStyle(PulseTheme.warningText)
            } else if let resetsAt = window.resetsAt {
                Text(WidgetFormat.shortReset(resetsAt, now: now)).foregroundStyle(PulseTheme.secondary)
            }
        } else {
            Text(WidgetFormat.stateText(service.state)).foregroundStyle(PulseTheme.secondary)
        }
    }
}

// MARK: - Éléments

/// « 🕒 Il y a 32 min » : les données ont plus de 15 min.
private struct StaleFootnote: View {
    let updatedAt: Date?
    let now: Date

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
            Text(WidgetFormat.updated(updatedAt, now: now).capitalizedFirst)
        }
        .font(.system(size: 11))
        .foregroundStyle(PulseTheme.secondary)
    }
}

/// Non connecté, expiré… à la place des limites.
private struct StateMessage: View {
    let service: WidgetSnapshot.Service

    var body: some View {
        Text(WidgetFormat.stateText(service.state))
            .font(.system(size: 12))
            .foregroundStyle(PulseTheme.secondary)
    }
}

/// Aucune donnée : Pulse n'a encore rien écrit, ou l'IA n'est pas suivie.
private struct NoDataView: View {
    let serviceID: String?
    let notFollowed: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let serviceID {
                LogoBadge(kind: WidgetSnapshot.Service.kind(for: serviceID), size: 19)
            }
            Text(notFollowed
                ? "Cette IA n'est pas suivie dans Pulse."
                : "Ouvrez Pulse pour afficher vos limites.")
                .font(.system(size: 12))
                .foregroundStyle(PulseTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Textes, en français

/// « 78% », comme dans l'app.
enum UsageFormatShort {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}

enum WidgetFormat {
    private static let locale = Locale(identifier: "fr_FR")

    /// Bleu, orange ou rouge selon les seuils de l'IA ; gris si périmé.
    static func color(_ percent: Double, _ service: WidgetSnapshot.Service, stale: Bool) -> Color {
        stale ? Color(hex: 0x636366)
            : PulseTheme.levelColor(percent, warning: service.warning, critical: service.critical)
    }

    /// « Reset à 17:00 », ou « Reset lun. 09:00 » un autre jour.
    static func reset(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? "Reset à \(ChartFormat.time(date))"
            : "Reset \(ChartFormat.dayAndTime(date))"
    }

    /// Plus court, pour le widget moyen : « Reset 18:10 », « Reset demain »,
    /// « Reset lun. », « Reset 1 déc. ».
    static func shortReset(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Reset \(ChartFormat.time(date))" }
        if calendar.isDateInTomorrow(date) { return "Reset demain" }
        if date.timeIntervalSince(now) < 6 * 86400 { return "Reset \(ChartFormat.day(date))" }
        return "Reset \(date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"
    }

    /// « à l'instant », « il y a 25 min », « il y a 2 h ».
    static func updated(_ date: Date?, now: Date) -> String {
        guard let date else { return "pas encore mis à jour" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        return "il y a \(minutes / 60) h"
    }

    /// « Session (5 h) » → (« Session », « 5 h »).
    static func labelLines(_ label: String) -> (String, String?) {
        guard let open = label.firstIndex(of: "("), let close = label.lastIndex(of: ")"), open < close else {
            return (label, nil)
        }
        let first = label[..<open].trimmingCharacters(in: .whitespaces)
        let second = label[label.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return (first.isEmpty ? label : first, second.isEmpty ? nil : second)
    }

    /// « de la session 5 h », « de la semaine », ou le nom de la limite.
    static func limitPhrase(_ label: String) -> String {
        let lower = label.lowercased(with: locale)
        guard lower.hasPrefix("session") || lower.hasPrefix("semaine") else { return label }
        return "de la " + lower.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
    }

    static func stateText(_ state: WidgetSnapshot.State) -> String {
        switch state {
        case .loading: "Chargement…"
        case .ok: "Données indisponibles"
        case .offline: "Hors ligne"
        case .notConnected: "Non connecté"
        case .expired: "Connexion expirée"
        case .blocked: "Accès bloqué"
        case .unavailable: "Données indisponibles"
        }
    }
}

extension String {
    /// « il y a 32 min » → « Il y a 32 min ».
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
