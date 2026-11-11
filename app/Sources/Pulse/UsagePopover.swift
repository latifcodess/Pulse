import PulseCore
import SwiftUI

/// Le contenu du popover. Il ne reçoit que des valeurs, pas le modèle, pour
/// pouvoir être affiché avec n'importe quel état.
struct UsagePopover: View {
    let state: AiState?
    let service: AiService
    let lastUpdated: Date?
    let thresholds: Thresholds
    /// Intervalle d'actualisation, en secondes.
    let refreshInterval: Int
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        // Redessine toutes les 30 s pour garder les durées à jour.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 14) {
                header
                if let message = Self.message(for: state, service: service, refreshInterval: refreshInterval) {
                    Label(message.text, systemImage: message.icon)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    WindowRow(window: window, color: thresholds.level(for: window.percent).color, now: context.date)
                }
                Divider()
                footer(now: context.date)
            }
            .padding(16)
        }
        .frame(width: 320)
    }

    private var windows: [UsageWindow] {
        switch state {
        case .ok(let usage): usage.windows
        case .offline(let last?): last.windows
        default: []
        }
    }

    /// La limite la plus proche d'être atteinte.
    private var highest: UsageWindow? {
        windows.max(by: { $0.percent < $1.percent })
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: service.logo(size: 20))
                .renderingMode(.template)
                .foregroundStyle(service.tint)
                .frame(width: 32, height: 32)
                .background(service.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            Text(service.title)
                .font(.headline)
            Spacer()
            if let highest {
                Text(UsageFormat.percent(highest.percent))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(thresholds.level(for: highest.percent).color ?? .primary)
            }
        }
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                iconButton("Actualiser", systemImage: "arrow.clockwise", action: onRefresh)
            }
            Text(UsageFormat.updated(lastUpdated, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            iconButton("Réglages", systemImage: "gearshape", action: onSettings)
            iconButton("Quitter", systemImage: "power", action: onQuit)
        }
    }

    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

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
}

private struct WindowRow: View {
    let window: UsageWindow
    let color: Color?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(UsageFormat.percent(window.percent))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(color ?? .secondary)
            }
            ProgressView(value: min(max(window.percent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(color ?? .accentColor)
            Text(UsageFormat.reset(window.resetsAt, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
            // La projection du cœur Rust : atteinte avant le reset, ou pas.
            if let fullAt = window.projectedFullAt {
                Label(UsageFormat.projection(fullAt, now: now), systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("Tiendra jusqu'au reset", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
