import PulseCore
import SwiftUI

/// Le contenu du popover. Il ne reçoit que des valeurs, pas le modèle, pour
/// pouvoir être affiché avec n'importe quel état.
struct UsagePopover: View {
    let state: AiState?
    let method: ClaudeAuthMethod
    let lastUpdated: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        // Redessine toutes les 30 s pour garder les durées à jour.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 14) {
                header
                if let message = Self.message(for: state, method: method) {
                    Label(message.text, systemImage: message.icon)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    WindowRow(window: window, now: context.date)
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
            Image(systemName: "sparkle")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            Text("Claude")
                .font(.headline)
            Spacer()
            if let highest {
                Text(UsageFormat.percent(highest.percent))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(UsageLevel(percent: highest.percent).color ?? .primary)
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

    static func message(for state: AiState?, method: ClaudeAuthMethod) -> (text: String, icon: String)? {
        switch state {
        case nil:
            ("Chargement…", "hourglass")
        case .ok:
            nil
        case .offline(.some):
            ("Hors ligne : dernières valeurs connues.", "wifi.slash")
        case .offline(nil):
            ("Hors ligne.", "wifi.slash")
        case .notConnected:
            ("Non connecté. Choisissez une méthode de connexion dans les Réglages.", "person.crop.circle.badge.questionmark")
        case .expired:
            switch method {
            case .claudeCode:
                ("Le token de Claude Code a expiré. Lancez Claude Code pour le renouveler.", "clock.badge.exclamationmark")
            case .claudeAi:
                ("La session claude.ai a expiré. Reconnectez-vous dans les Réglages.", "clock.badge.exclamationmark")
            }
        case .blocked:
            ("Accès temporairement bloqué. Nouvel essai dans 2 min.", "hand.raised")
        case .unavailable:
            ("Données indisponibles.", "exclamationmark.triangle")
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        let color = UsageLevel(percent: window.percent).color
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
        }
    }
}
