import AppKit
import PulseCore
import SwiftUI

/// La fenêtre Réglages : un onglet Général et un onglet par IA.
struct SettingsView: View {
    let app: AppModel

    /// L'onglet affiché : "general" ou la clé d'une IA. Le popover le change
    /// pour ouvrir directement l'onglet de son IA.
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsTab(app: app)
                .tabItem { Label("Général", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            AlertsSettingsTab(alerts: app.alertCenter, services: app.services.map(\.service))
                .tabItem { Label("Alertes", systemImage: "bell") }
                .tag(SettingsTab.alerts)

            ForEach(app.services, id: \.service) { model in
                ServiceSettingsTab(app: app, model: model)
                    .tabItem { Label { Text(model.service.title) } icon: { Image(nsImage: model.service.logo()) } }
                    .tag(model.service.storageKey)
            }
        }
        .frame(width: 520, height: 700)
    }
}

extension View {
    /// Une note sous une section : en gris, alignée à gauche comme le reste
    /// du formulaire (par défaut, macOS l'aligne à droite).
    func sectionFooter() -> some View {
        foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum SettingsTab {
    static let storageKey = "settingsTab"
    static let general = "general"
    static let alerts = "alerts"
}

// MARK: - Général

private struct GeneralSettingsTab: View {
    let app: AppModel

    var body: some View {
        @Bindable var launchAtLogin = app.launchAtLogin
        Form {
            Section("Démarrage") {
                Toggle("Ouvrir Pulse au démarrage de la session", isOn: $launchAtLogin.isEnabled)
                if launchAtLogin.needsApproval {
                    LabeledContent {
                        Button("Ouvrir les Réglages Système") { launchAtLogin.openSystemSettings() }
                    } label: {
                        Text("macOS attend votre accord dans Réglages Système › Général › Ouverture.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = launchAtLogin.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(app.services, id: \.service) { model in
                    @Bindable var model = model
                    Toggle(isOn: $model.isEnabled) {
                        Label { Text(model.service.title) } icon: { Image(nsImage: model.service.logo()) }
                    }
                }
            } header: {
                Text("IA suivies")
            } footer: {
                Text("Si aucune IA n'est suivie, l'icône de Pulse reste dans la barre des menus pour rouvrir ces réglages.")
                    .sectionFooter()
            }

            UpdatesSection(updater: app.updater)

            Section {
                Button("Quitter Pulse") { NSApplication.shared.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.reload() }
    }
}

// MARK: - Mises à jour

private struct UpdatesSection: View {
    @Bindable var updater: Updater

    var body: some View {
        Section {
            LabeledContent("Version installée", value: updater.currentVersion)
            Toggle("Rechercher automatiquement (une fois par jour)", isOn: $updater.automaticChecks)

            switch updater.phase {
            case .available(let info):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Pulse \(info.version) est disponible", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                    if !info.notes.isEmpty {
                        Text(info.notes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("Installer et relancer") {
                            Task { await updater.install(info) }
                        }
                        .buttonStyle(.borderedProminent)
                        if let page = URL(string: info.pageUrl), !info.pageUrl.isEmpty {
                            Link("Voir sur GitHub", destination: page)
                        }
                    }
                }
            case .downloading(let info):
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Téléchargement de Pulse \(info.version)…")
                }
            case .installing:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Installation… Pulse va redémarrer.")
                }
            default:
                LabeledContent {
                    if case .checking = updater.phase {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Rechercher maintenant") {
                            Task { await updater.check(userInitiated: true) }
                        }
                    }
                } label: {
                    UpdateStatusText(updater: updater)
                }
            }
        } header: {
            Text("Mises à jour")
        } footer: {
            Text("Les mises à jour viennent des releases GitHub de Pulse. Chaque téléchargement est vérifié (empreinte SHA-256) avant l'installation.")
                .sectionFooter()
        }
    }
}

private struct UpdateStatusText: View {
    let updater: Updater

    var body: some View {
        switch updater.phase {
        case .checking:
            Text("Recherche en cours…")
        case .upToDate:
            Label {
                Text(upToDateText)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text("Pas encore recherché")
                .foregroundStyle(.secondary)
        }
    }

    /// « Pulse est à jour (vérifié à 14:32) ».
    private var upToDateText: String {
        guard let lastCheck = updater.lastCheck else { return "Pulse est à jour" }
        return "Pulse est à jour (vérifié à \(UsageFormat.hourMinute(lastCheck)))"
    }
}

// MARK: - Une IA

private struct ServiceSettingsTab: View {
    let app: AppModel
    @Bindable var model: UsageModel

    private var service: AiService { model.service }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle("Suivre \(service.title)", isOn: $model.isEnabled)
            } footer: {
                Text("Sans suivi, la puce est retirée de la barre des menus et Pulse ne fait plus aucune requête pour \(service.title).")
                    .sectionFooter()
            }

            Section("Connexion") {
                ConnectionStatusRow(model: model)
                if service == .claude {
                    ClaudeConnectionControls(app: app, model: model)
                } else {
                    CliConnectionControls(service: service, isSignedIn: model.isSignedIn)
                }
                Button("Vérifier maintenant") { model.refreshNow() }
                    .disabled(!model.isEnabled || model.isRefreshing)
            }

            Section("Barre des menus") {
                Picker("Valeur affichée", selection: $settings.display) {
                    ForEach(BarDisplay.allCases) { Text($0.title).tag($0) }
                }
                Picker("Pourcentage", selection: $settings.valueMode) {
                    ForEach(ValueMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Aperçu") {
                    BarPreview(model: model)
                }
            }

            Section {
                Picker("Actualiser toutes les", selection: $model.refreshInterval) {
                    ForEach(ServiceSettings.intervals, id: \.self) { seconds in
                        Text(UsageFormat.interval(seconds)).tag(seconds)
                    }
                }
                Stepper(
                    value: $settings.thresholds.warning,
                    in: 5...(settings.thresholds.critical - 5),
                    step: 5
                ) {
                    ThresholdLabel(title: "Orange au-delà de", value: settings.thresholds.warning, color: .orange)
                }
                Stepper(
                    value: $settings.thresholds.critical,
                    in: (settings.thresholds.warning + 5)...100,
                    step: 5
                ) {
                    ThresholdLabel(title: "Rouge au-delà de", value: settings.thresholds.critical, color: .red)
                }
            } header: {
                Text("Actualisation et alertes")
            } footer: {
                Text("Les seuils portent sur le pourcentage utilisé, même si la puce affiche le restant.")
                    .sectionFooter()
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThresholdLabel: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        LabeledContent {
            Text("\(value) %").monospacedDigit()
        } label: {
            Label {
                Text(title)
            } icon: {
                Circle().fill(color).frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Connexion

private struct ConnectionStatusRow: View {
    let model: UsageModel

    var body: some View {
        let status = ConnectionStatus(model: model)
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("État") {
                Label {
                    Text(status.title)
                } icon: {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                }
            }
            if model.isEnabled, model.state != nil,
                let message = UsagePopover.message(
                    for: model.state, service: model.service, refreshInterval: model.refreshInterval)
            {
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConnectionStatus {
    let title: String
    let color: Color

    @MainActor
    init(model: UsageModel) {
        guard model.isEnabled else {
            (title, color) = ("Non suivi", .gray)
            return
        }
        switch model.state {
        case nil: (title, color) = ("Vérification…", .gray)
        case .ok: (title, color) = ("Connecté", .green)
        case .offline: (title, color) = ("Hors ligne", .gray)
        case .notConnected: (title, color) = ("Non connecté", .gray)
        case .expired: (title, color) = ("Connexion expirée", .orange)
        case .blocked: (title, color) = ("Connecté, accès bloqué", .orange)
        case .unavailable: (title, color) = ("Données indisponibles", .orange)
        }
    }
}

/// Claude : choix de la méthode, et connexion au compte claude.ai dans l'app.
private struct ClaudeConnectionControls: View {
    let app: AppModel
    let model: UsageModel

    @AppStorage(ClaudeAuthMethod.storageKey) private var method = ClaudeAuthMethod.claudeCode
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Picker("Méthode", selection: $method) {
            ForEach(ClaudeAuthMethod.allCases) { method in
                Text(method.title).tag(method)
            }
        }
        .onChange(of: method) {
            model.refreshNow()
        }

        switch method {
        case .claudeAi:
            if app.claudeAccount.claudeAiConnected {
                LabeledContent("Compte claude.ai") {
                    Button("Se déconnecter") { app.disconnectClaudeAi() }
                }
            } else {
                LabeledContent("Compte claude.ai") {
                    Button("Se connecter…") {
                        openWindow(id: WindowID.claudeLogin)
                        NSApp.activate()
                    }
                }
            }
        case .claudeCode:
            CliConnectionControls(service: .claude, isSignedIn: model.isSignedIn)
        }
    }
}

/// Les IA connectées par un outil en ligne de commande. Pulse lit leurs
/// identifiants sans jamais les modifier : la connexion et la déconnexion se
/// font dans l'outil lui-même.
private struct CliConnectionControls: View {
    let service: AiService
    let isSignedIn: Bool

    var body: some View {
        let instruction = isSignedIn ? service.logoutInstruction : service.loginInstruction
        VStack(alignment: .leading, spacing: 8) {
            Text(isSignedIn ? "Se déconnecter" : "Se connecter")
                .font(.subheadline.weight(.medium))
            if let command = instruction.command {
                HStack {
                    Text(command)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    Spacer()
                    Button("Copier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    Button("Ouvrir le Terminal") {
                        NSWorkspace.shared.openApplication(
                            at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                            configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
            Text(instruction.note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CliInstruction {
    let command: String?
    let note: String
}

extension AiService {
    fileprivate var loginInstruction: CliInstruction {
        switch self {
        case .claude:
            CliInstruction(command: "claude", note: "Dans Claude Code, tapez /login. Pulse lit ensuite le token dans le Trousseau.")
        case .chatGpt:
            CliInstruction(command: "codex login", note: "Connectez-vous avec votre compte ChatGPT dans le navigateur qui s'ouvre.")
        case .gemini:
            CliInstruction(command: "gemini", note: "Choisissez « Login with Google », puis connectez-vous dans le navigateur.")
        case .copilot:
            CliInstruction(command: "gh auth login", note: "Si gh n'est pas installé : brew install gh.")
        }
    }

    fileprivate var logoutInstruction: CliInstruction {
        switch self {
        case .claude:
            CliInstruction(command: "claude", note: "Dans Claude Code, tapez /logout. Pulse ne modifie jamais ses identifiants.")
        case .chatGpt:
            CliInstruction(command: "codex logout", note: "Pulse ne modifie jamais les identifiants de Codex.")
        case .gemini:
            CliInstruction(command: nil, note: "Dans Gemini CLI, tapez /auth pour changer de compte. Pulse ne modifie jamais ses identifiants.")
        case .copilot:
            CliInstruction(command: "gh auth logout", note: "Pulse ne modifie jamais les identifiants de GitHub CLI.")
        }
    }
}

// MARK: - Aperçu

/// La puce telle qu'elle apparaîtra, avec les valeurs actuelles si elles sont
/// connues, sinon avec des valeurs d'exemple.
private struct BarPreview: View {
    let model: UsageModel

    private static let sample = [
        UsageWindow(label: "Session", percent: 42, resetsAt: nil, projectedFullAt: nil),
        UsageWindow(label: "Semaine", percent: 81, resetsAt: nil, projectedFullAt: nil),
    ]

    var body: some View {
        let usesSample = model.windows.isEmpty
        let content = UsageModel.barContent(
            windows: usesSample ? Self.sample : model.windows, settings: model.settings)
        VStack(alignment: .trailing, spacing: 4) {
            MenuBarLabel(logo: model.service.logo(), text: content.text, level: content.level)
                .font(Font(NSFont.menuBarFont(ofSize: 0)))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.bar, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Text(usesSample ? "Valeurs d'exemple" : "Valeurs actuelles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
