import PulseCore
import SwiftUI

/// L'onglet Alertes : l'autorisation de macOS, puis la liste des règles.
struct AlertsSettingsTab: View {
    @Bindable var alerts: AlertCenter
    let services: [AiService]

    var body: some View {
        Form {
            Section("Notifications") {
                AuthorizationRow(alerts: alerts)
                Button("Envoyer une notification de test") { alerts.sendTest() }
                    .disabled(!alerts.isAuthorized)
            }

            Section {
                if alerts.rules.isEmpty {
                    Text("Aucune alerte.")
                        .foregroundStyle(.secondary)
                }
                ForEach($alerts.rules, id: \.id) { $rule in
                    AlertRuleRow(rule: $rule, services: services) {
                        alerts.rules.removeAll { $0.id == rule.id }
                    }
                }
            } header: {
                Text("Alertes")
            } footer: {
                Text("Chaque alerte ne se déclenche qu'une fois, puis se réarme quand la valeur redescend sous le seuil.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Menu("Ajouter une alerte") {
                    Button("Limite au-dessus d'un seuil") {
                        alerts.addRule(.threshold(windowIndex: 0, percent: 80))
                    }
                    Button("De nouveau disponible") {
                        alerts.addRule(.available(afterPercent: 80))
                    }
                    Button("Session expirée") {
                        alerts.addRule(.expired)
                    }
                    Button("Limite bientôt atteinte (projection)") {
                        alerts.addRule(.projection(minutes: 30))
                    }
                }
                Button("Rétablir les alertes par défaut") { alerts.resetRules() }
            }
        }
        .formStyle(.grouped)
        .task { await alerts.reloadAuthorization() }
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
            LabeledContent("Autorisation") {
                Label("Autorisées", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .denied:
            LabeledContent {
                Button("Ouvrir les Réglages Système") { alerts.openSystemSettings() }
            } label: {
                Text("Les notifications de Pulse sont désactivées dans macOS.")
                    .foregroundStyle(.orange)
            }
        default:
            LabeledContent {
                Button("Autoriser") {
                    Task { await alerts.requestAuthorizationIfNeeded() }
                }
            } label: {
                Text("macOS n'a pas encore autorisé les notifications de Pulse.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Une règle : interrupteur, type, IA concernée et réglages propres au type.
private struct AlertRuleRow: View {
    @Binding var rule: AlertRule
    let services: [AiService]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $rule.enabled) {
                    Label(rule.kind.title, systemImage: rule.kind.symbol)
                        .font(.headline)
                }
                .toggleStyle(.switch)
                Button(role: .destructive, action: onDelete) {
                    Label("Supprimer", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Supprimer cette alerte")
            }

            Group {
                Picker("IA", selection: $rule.service) {
                    Text("Toutes les IA").tag(AiService?.none)
                    ForEach(services, id: \.self) { service in
                        Text(service.title).tag(AiService?.some(service))
                    }
                }

                switch rule.kind {
                case .threshold:
                    Picker("Limite", selection: windowIndex) {
                        Text("1re limite").tag(UInt32(0))
                        Text("2e limite").tag(UInt32(1))
                        Text("3e limite").tag(UInt32(2))
                    }
                    PercentStepper(title: "Au-dessus de", value: percent)
                case .available:
                    PercentStepper(title: "Si la fenêtre précédente a dépassé", value: percent)
                case .expired:
                    Text("Un clic sur la notification ouvre les réglages de l'IA.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .projection:
                    Stepper(value: minutes, in: 5...120, step: 5) {
                        LabeledContent("Si atteinte dans moins de") {
                            Text("\(minutes.wrappedValue) min").monospacedDigit()
                        }
                    }
                    Text("Au rythme actuel de consommation. Une seule fois par fenêtre.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!rule.enabled)
        }
        .padding(.vertical, 4)
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
    private var percent: Binding<Double> {
        Binding {
            switch rule.kind {
            case .threshold(_, let percent): percent
            case .available(let percent): percent
            case .expired, .projection: 0
            }
        } set: { percent in
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

private struct PercentStepper: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        Stepper(value: $value, in: 5...100, step: 5) {
            LabeledContent(title) {
                Text(UsageFormat.percent(value)).monospacedDigit()
            }
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
