import AppKit
import SwiftUI
import WidgetKit

// MARK: - Petit : une IA

struct SingleServiceView: View {
    let entry: PulseEntry

    var body: some View {
        if let service = entry.snapshot?.services.first(where: { $0.id == entry.serviceID }) {
            ServiceSummary(service: service, now: entry.date)
        } else {
            NoDataView(serviceID: entry.serviceID)
        }
    }
}

private struct ServiceSummary: View {
    let service: WidgetSnapshot.Service
    let now: Date

    var body: some View {
        let stale = service.isStale(at: now)
        VStack(alignment: .leading, spacing: 6) {
            ServiceHeader(service: service)

            Group {
                if let window = service.windows.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WidgetFormat.percent(window.percent))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetFormat.color(window.percent, service) ?? .primary)
                        Text(window.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        UsageBar(percent: window.percent, color: WidgetFormat.color(window.percent, service))
                        WindowFootnote(window: window, now: now)
                    }
                } else {
                    Text(WidgetFormat.stateText(service.state))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .grayedOut(stale)

            Spacer(minLength: 0)
            if stale, service.updatedAt != nil {
                Text(WidgetFormat.updated(service.updatedAt, now: now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Réinitialisation, ou projection si la limite sera atteinte avant.
private struct WindowFootnote: View {
    let window: WidgetSnapshot.Window
    let now: Date

    var body: some View {
        if let fullAt = window.projectedFullAt {
            Text("Limite vers \(WidgetFormat.time(fullAt, now: now))")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if let resetsAt = window.resetsAt {
            Text("Reset \(WidgetFormat.time(resetsAt, now: now))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Moyen : toutes les IA

struct AllServicesView: View {
    let entry: PulseEntry

    var body: some View {
        let services = entry.snapshot?.services.filter(\.followed) ?? []
        if services.isEmpty {
            NoDataView(serviceID: nil)
        } else {
            // Une grille de 2 colonnes : jusqu'à 4 IA tiennent dans un widget moyen.
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(Array(stride(from: 0, to: min(services.count, 4), by: 2)), id: \.self) { start in
                    GridRow {
                        ServiceCell(service: services[start], now: entry.date)
                        if start + 1 < services.count {
                            ServiceCell(service: services[start + 1], now: entry.date)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ServiceCell: View {
    let service: WidgetSnapshot.Service
    let now: Date

    var body: some View {
        let stale = service.isStale(at: now)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                ServiceLogoView(id: service.id, size: 12)
                Text(service.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let window = service.windows.first {
                    Text(WidgetFormat.percent(window.percent))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetFormat.color(window.percent, service) ?? .primary)
                        .grayedOut(stale)
                }
            }
            if let window = service.windows.first {
                UsageBar(percent: window.percent, color: WidgetFormat.color(window.percent, service))
                    .grayedOut(stale)
                Text(detail(window, stale: stale))
                    .font(.caption2)
                    .foregroundStyle(window.projectedFullAt != nil && !stale ? Color.orange : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(WidgetFormat.stateText(service.state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « limite vers 15:40 », « reset 17:00 », ou « il y a 26 min » si les données sont anciennes.
    private func detail(_ window: WidgetSnapshot.Window, stale: Bool) -> String {
        if stale, service.updatedAt != nil {
            return WidgetFormat.updated(service.updatedAt, now: now)
        }
        if let fullAt = window.projectedFullAt {
            return "Limite vers \(WidgetFormat.time(fullAt, now: now))"
        }
        if let resetsAt = window.resetsAt {
            return "Reset \(WidgetFormat.time(resetsAt, now: now))"
        }
        return window.label
    }
}

// MARK: - Éléments communs

private struct ServiceHeader: View {
    let service: WidgetSnapshot.Service

    var body: some View {
        HStack(spacing: 6) {
            ServiceLogoView(id: service.id, size: 15)
            Text(service.title)
                .font(.headline)
                .lineLimit(1)
        }
    }
}

private struct ServiceLogoView: View {
    let id: String
    let size: CGFloat

    var body: some View {
        if let kind = WidgetFormat.logoKind(id) {
            Image(nsImage: ServiceLogo.image(kind, size: size))
                .renderingMode(.template)
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

/// Une barre de progression dessinée à la main : ProgressView ne s'affiche
/// pas toujours dans un widget.
private struct UsageBar: View {
    let percent: Double
    let color: Color?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color ?? .accentColor)
                    .frame(width: geometry.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 5)
    }
}

/// Aucune donnée : Pulse n'a encore rien écrit, ou l'IA n'est pas suivie.
private struct NoDataView: View {
    let serviceID: String?

    var body: some View {
        VStack(spacing: 6) {
            if let serviceID, let kind = WidgetFormat.logoKind(serviceID) {
                Image(nsImage: ServiceLogo.image(kind, size: 22))
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
            }
            Text("Ouvrez Pulse pour afficher vos limites.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Données de plus de 15 min : en grisé.
    func grayedOut(_ stale: Bool) -> some View {
        grayscale(stale ? 1 : 0)
            .opacity(stale ? 0.45 : 1)
    }
}

// MARK: - Textes, en français

enum WidgetFormat {
    private static let locale = Locale(identifier: "fr_FR")

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    /// « 17:00 », ou « mar. 17:00 » si ce n'est pas aujourd'hui.
    static func time(_ date: Date, now: Date) -> String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return time
        }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(locale)) + " " + time
    }

    /// « mis à jour il y a 25 min », « … il y a 2 h ».
    static func updated(_ date: Date?, now: Date) -> String {
        guard let date else { return "pas encore mis à jour" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 60 {
            return "mis à jour il y a \(minutes) min"
        }
        return "mis à jour il y a \(minutes / 60) h"
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

    /// Orange puis rouge, selon les seuils réglés dans Pulse.
    static func color(_ percent: Double, _ service: WidgetSnapshot.Service) -> Color? {
        if percent > Double(service.critical) { return .red }
        if percent > Double(service.warning) { return .orange }
        return nil
    }

    static func logoKind(_ id: String) -> ServiceLogo.Kind? {
        switch id {
        case "claude": .claude
        case "chatgpt": .chatGpt
        case "gemini": .gemini
        case "copilot": .copilot
        default: nil
        }
    }
}
