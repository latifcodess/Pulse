import PulseCore
import SwiftUI

/// La page Alertes : l'autorisation de macOS, puis la liste des règles.
struct AlertsSettingsPage: View {
    @Bindable var alerts: AlertCenter
    let services: [AiService]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle("Alertes")

            SettingsSection(title: "Notifications", padding: EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16), spacing: 0) {
                AuthorizationRow(alerts: alerts)
                    .padding(.top, 4)
                SettingsRow(title: "Notification de test", subtitle: "Pour voir à quoi ressemble une alerte", showsDivider: false) {
                    Button("Envoyer") { alerts.sendTest() }
                        .buttonStyle(.pulse)
                        .disabled(!alerts.isAuthorized)
                }
            }

            SettingsSection(title: "Règles", spacing: 10) {
                if alerts.rules.isEmpty {
                    SettingsNote("Aucune alerte.")
                }
                ForEach($alerts.rules, id: \.id) { $rule in
                    AlertRuleCard(rule: $rule, services: services) {
                        withAnimation(.smooth(duration: 0.25)) {
                            alerts.rules.removeAll { $0.id == rule.id }
                        }
                    }
                }
                SettingsNote("Chaque alerte ne se déclenche qu'une fois, puis se réarme quand la valeur redescend sous le seuil.")
                HStack(spacing: 10) {
                    Menu {
                        Button("Limite au-dessus d'un seuil") { add(.threshold(windowIndex: 0, percent: 80)) }
                        Button("De nouveau disponible") { add(.available(afterPercent: 80)) }
                        Button("Session expirée") { add(.expired) }
                        Button("Limite bientôt atteinte (projection)") { add(.projection(minutes: 30)) }
                    } label: {
                        Label("Ajouter une alerte", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.pulsePrimary)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Button("Rétablir les alertes par défaut") { alerts.resetRules() }
                        .buttonStyle(.pulse)
                }
                .padding(.top, 2)
            }
        }
        .task { await alerts.reloadAuthorization() }
    }

    private func add(_ kind: AlertKind) {
        withAnimation(.smooth(duration: 0.25)) { alerts.addRule(kind) }
    }
}

extension AlertCenter {
    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional
    }
}

private struct AuthorizationRow: View {
    let alerts: AlertCenter

    var body: some View {
        switch alerts.authorization {
        case .authorized, .provisional, .ephemeral:
            SettingsRow(title: "Autorisation") {
                HStack(spacing: 6) {
                    StatusDot(color: PulseTheme.connected)
                    Text("Autorisées").font(.system(size: 13)).foregroundStyle(PulseTheme.secondary)
                }
            }
        case .denied:
            SettingsRow(title: "Autorisation", subtitle: "Les notifications de Pulse sont désactivées dans macOS.") {
                Button("Ouvrir les Réglages Système") { alerts.openSystemSettings() }
                    .buttonStyle(.pulse)
            }
        default:
            SettingsRow(title: "Autorisation", subtitle: "macOS n'a pas encore autorisé les notifications de Pulse.") {
                Button("Autoriser") {
                    Task { await alerts.requestAuthorizationIfNeeded() }
                }
                .buttonStyle(.pulsePrimary)
            }
        }
    }
}

/// Une règle : interrupteur, type, IA concernée et réglages propres au type.
private struct AlertRuleCard: View {
    @Binding var rule: AlertRule
    let services: [AiService]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: rule.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(rule.enabled ? PulseTheme.accent : PulseTheme.tertiary)
                    .frame(width: 18)
                Text(rule.kind.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Supprimer cette alerte")
                .accessibilityLabel("Supprimer cette alerte")
                PulseSwitch(isOn: $rule.enabled, label: rule.kind.title)
            }

            Group {
                HStack(spacing: 16) {
                    labeled("IA") {
                        PopupMenu(
                            options: [(AiService?.none, "Toutes les IA")] + services.map { (AiService?.some($0), $0.title) },
                            selection: $rule.service,
                            label: "IA")
                    }
                    if case .threshold = rule.kind {
                        labeled("Limite") {
                            PopupMenu(
                                options: [(UInt32(0), "1re limite"), (1, "2e limite"), (2, "3e limite")],
                                selection: windowIndex,
                                label: "Limite")
                        }
                    }
                    Spacer(minLength: 0)
                }

                switch rule.kind {
                case .threshold:
                    ThresholdSlider(title: "Au-dessus de", value: percent, range: 5...100, color: PulseTheme.warning)
                case .available:
                    ThresholdSlider(
                        title: "Si la fenêtre précédente a dépassé", value: percent, range: 5...100,
                        color: PulseTheme.normal)
                case .expired:
                    SettingsNote("Un clic sur la notification ouvre les réglages de l'IA.")
                case .projection:
                    ThresholdSlider(
                        title: "Si atteinte dans moins de", value: minutes, range: 5...120,
                        color: PulseTheme.normal, scale: 0...120, unit: "min")
                    SettingsNote("Au rythme actuel de consommation. Une seule fois par fenêtre.")
                }
            }
            .disabled(!rule.enabled)
            .opacity(rule.enabled ? 1 : 0.5)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PulseTheme.cardBorder))
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(PulseTheme.secondary)
            content()
        }
    }

    /// Le n° de limite d'une règle de seuil.
    private var windowIndex: Binding<UInt32> {
        Binding {
            if case .threshold(let index, _) = rule.kind { index } else { 0 }
        } set: { index in
            if case .threshold(_, let percent) = rule.kind {
                rule.kind = .threshold(windowIndex: index, percent: percent)
            }
        }
    }

    /// Le pourcentage d'une règle de seuil ou « de nouveau disponible ».
    private var percent: Binding<Int> {
        Binding {
            switch rule.kind {
            case .threshold(_, let percent): Int(percent.rounded())
            case .available(let percent): Int(percent.rounded())
            case .expired, .projection: 0
            }
        } set: { value in
            let percent = Double(value)
            switch rule.kind {
            case .threshold(let index, _): rule.kind = .threshold(windowIndex: index, percent: percent)
            case .available: rule.kind = .available(afterPercent: percent)
            case .expired, .projection: break
            }
        }
    }

    /// Le délai d'une règle de projection, en minutes.
    private var minutes: Binding<Int> {
        Binding {
            if case .projection(let minutes) = rule.kind { Int(minutes) } else { 30 }
        } set: { minutes in
            rule.kind = .projection(minutes: UInt32(minutes))
        }
    }
}

extension AlertKind {
    var title: String {
        switch self {
        case .threshold: "Limite au-dessus d'un seuil"
        case .available: "De nouveau disponible"
        case .expired: "Session expirée"
        case .projection: "Limite bientôt atteinte"
        }
    }

    var symbol: String {
        switch self {
        case .threshold: "gauge.with.dots.needle.67percent"
        case .available: "arrow.counterclockwise.circle"
        case .expired: "clock.badge.exclamationmark"
        case .projection: "chart.line.uptrend.xyaxis"
        }
    }
}
