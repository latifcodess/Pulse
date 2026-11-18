import AppKit
import PulseCore
import SwiftUI

/// La page d'une IA dans les réglages (maquette
/// design/pulse-maquettes/Settings.dc.html) : suivi, connexion, affichage,
/// aperçu et actualisation.
struct ServiceSettingsPage: View {
    let app: AppModel
    @Bindable var model: UsageModel

    private var service: AiService { model.service }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PageTitle(service.title)
                Spacer()
                HStack(spacing: 10) {
                    Text("Suivre")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseTheme.secondary)
                    PulseSwitch(isOn: $model.isEnabled, label: "Suivre \(service.title)")
                }
            }
            if !model.isEnabled {
                SettingsNote("Sans suivi, \(service.title) est retiré de la barre des menus et Pulse ne fait plus aucune requête pour lui.")
            }

            if service == .claude {
                ClaudeConnectionSection(app: app, model: model)
            } else {
                AccountConnectionSection(app: app, model: model)
            }
            DisplaySection(model: model)
            PreviewSection(app: app, model: model)
        }
    }
}

// MARK: - Connexion

/// Claude : Claude Code, ou le compte claude.ai connecté dans Pulse.
private struct ClaudeConnectionSection: View {
    let app: AppModel
    let model: UsageModel

    @AppStorage(ClaudeAuthMethod.storageKey) private var method = ClaudeAuthMethod.claudeCode

    var body: some View {
        SettingsSection(title: "Connexion") {
            SegmentedControl(
                options: ClaudeAuthMethod.allCases.map { ($0, $0.title) },
                selection: $method,
                label: "Méthode de connexion")
            .onChange(of: method) { model.refreshNow() }

            switch method {
            case .claudeCode:
                ConnectionStatusLine(
                    model: model, method: "via Claude Code",
                    plan: app.claudeAccount.plan
                ) {
                    RefreshButton(model: model)
                }
                CliInstructions(service: .claude, isSignedIn: model.isSignedIn)
            case .claudeAi:
                let connected = app.claudeAccount.claudeAiConnected
                ConnectionStatusLine(model: model, method: "avec le compte claude.ai") {
                    if connected {
                        Button("Se déconnecter") { app.disconnectClaudeAi() }
                            .buttonStyle(.pulse)
                    } else {
                        Button("Se connecter…") { WindowRouter.shared.show(WindowID.claudeLogin) }
                            .buttonStyle(.pulsePrimary)
                    }
                }
            }
        }
    }
}

/// ChatGPT, Gemini, Copilot : l'outil en ligne de commande, ou un compte
/// connecté dans Pulse.
private struct AccountConnectionSection: View {
    let app: AppModel
    let model: UsageModel
    @AppStorage private var method: ConnectionMethod

    init(app: AppModel, model: UsageModel) {
        self.app = app
        self.model = model
        _method = AppStorage(wrappedValue: .cli, ConnectionMethod.storageKey(for: model.service))
    }

    private var service: AiService { model.service }

    var body: some View {
        SettingsSection(title: "Connexion") {
            SegmentedControl(
                options: [(ConnectionMethod.cli, service.cliName), (.account, service.accountName)],
                selection: $method,
                label: "Méthode de connexion")
            .onChange(of: method) { model.refreshNow() }

            switch method {
            case .cli:
                ConnectionStatusLine(model: model, method: "via \(service.cliName)") {
                    RefreshButton(model: model)
                }
                CliInstructions(service: service, isSignedIn: model.isSignedIn)
            case .account:
                let connected = app.account(for: service)?.isConnected == true
                ConnectionStatusLine(model: model, method: "avec le \(service.accountName.lowercasedFirst)") {
                    if connected {
                        Button("Se déconnecter") { app.disconnectAccount(service) }
                            .buttonStyle(.pulse)
                    } else {
                        signInButton
                    }
                }
                if !connected {
                    signInNote
                }
            }
        }
    }

    @ViewBuilder
    private var signInButton: some View {
        switch service {
        case .chatGpt:
            Button("Se connecter…") { WindowRouter.shared.show(WindowID.chatGptLogin) }
                .buttonStyle(.pulsePrimary)
        case .copilot:
            Button("Se connecter…") { WindowRouter.shared.show(WindowID.githubLogin) }
                .buttonStyle(.pulsePrimary)
        case .gemini:
            if case .waiting = app.googleSignIn.phase {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("Annuler") { app.googleSignIn.cancel() }
                        .buttonStyle(.pulse)
                }
            } else {
                Button("Se connecter avec Google…") { app.signInWithGoogle() }
                    .buttonStyle(.pulsePrimary)
            }
        case .claude:
            EmptyView()
        }
    }

    @ViewBuilder
    private var signInNote: some View {
        switch service {
        case .chatGpt:
            SettingsNote("Connectez-vous avec l'adresse e-mail de votre compte : la connexion via Google, Apple ou Microsoft peut être refusée dans cette fenêtre.")
        case .gemini:
            switch app.googleSignIn.phase {
            case .waiting:
                SettingsNote("Connexion en cours dans votre navigateur…")
            case .failed(let message):
                SettingsNote(message, color: PulseTheme.warningText)
            case .idle:
                EmptyView()
            }
        case .claude, .copilot:
            EmptyView()
        }
    }
}

/// « ● Connecté via Claude Code · plan Max », un bouton à droite, et le
/// détail du problème s'il y en a un.
private struct ConnectionStatusLine<Trailing: View>: View {
    let model: UsageModel
    /// « via Claude Code », « avec le compte ChatGPT ».
    let method: String
    var plan: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        let status = ConnectionStatus(model: model, method: method, plan: plan)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(color: status.color)
                Text(status.title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                trailing
            }
            if model.isEnabled, model.state != nil,
                let message = StateMessage.message(
                    for: model.state, service: model.service, refreshInterval: model.refreshInterval)
            {
                SettingsNote(message.text)
            }
        }
    }
}

private struct ConnectionStatus {
    let title: String
    let color: Color

    @MainActor
    init(model: UsageModel, method: String, plan: String?) {
        guard model.isEnabled else {
            (title, color) = ("Non suivi", PulseTheme.disconnected)
            return
        }
        switch model.state {
        case nil: (title, color) = ("Vérification…", PulseTheme.disconnected)
        case .ok:
            let planText = plan.map { " · plan \($0)" } ?? ""
            (title, color) = ("Connecté \(method)\(planText)", PulseTheme.connected)
        case .offline: (title, color) = ("Hors ligne", PulseTheme.disconnected)
        case .notConnected: (title, color) = ("Non connecté", PulseTheme.disconnected)
        case .expired: (title, color) = ("Connexion expirée", PulseTheme.warning)
        case .blocked: (title, color) = ("Connecté, accès bloqué", PulseTheme.warning)
        case .unavailable: (title, color) = ("Données indisponibles", PulseTheme.warning)
        }
    }
}

private struct RefreshButton: View {
    let model: UsageModel

    var body: some View {
        Button("Vérifier maintenant") { model.refreshNow() }
            .buttonStyle(.pulse)
            .disabled(!model.isEnabled || model.isRefreshing)
    }
}

/// Les IA connectées par un outil en ligne de commande. Pulse lit leurs
/// identifiants sans jamais les modifier : la connexion et la déconnexion se
/// font dans l'outil, d'où la commande à la place de « Se déconnecter ».
private struct CliInstructions: View {
    let service: AiService
    let isSignedIn: Bool

    var body: some View {
        let instruction = isSignedIn ? service.logoutInstruction : service.loginInstruction
        VStack(alignment: .leading, spacing: 8) {
            Text(isSignedIn ? "Pour se déconnecter, dans le Terminal :" : "Pour se connecter, dans le Terminal :")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PulseTheme.secondary)
            if let command = instruction.command {
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                    Button("Copier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .buttonStyle(.pulse)
                    Button("Ouvrir le Terminal") {
                        NSWorkspace.shared.openApplication(
                            at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                            configuration: NSWorkspace.OpenConfiguration())
                    }
                    .buttonStyle(.pulse)
                }
            }
            SettingsNote(instruction.note)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(PulseTheme.cardBorder).frame(height: 1)
        }
    }
}

private struct CliInstruction {
    let command: String?
    let note: String
}

extension AiService {
    /// L'outil en ligne de commande qui fournit les identifiants.
    var cliName: String {
        switch self {
        case .claude: "Claude Code"
        case .chatGpt: "Codex CLI"
        case .gemini: "Gemini CLI"
        case .copilot: "GitHub CLI"
        }
    }

    /// Le compte qu'on peut connecter directement dans Pulse.
    var accountName: String {
        switch self {
        case .claude: "Compte claude.ai"
        case .chatGpt: "Compte ChatGPT"
        case .gemini: "Compte Google"
        case .copilot: "Compte GitHub"
        }
    }

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

extension String {
    /// « Compte ChatGPT » → « compte ChatGPT ».
    var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}

// MARK: - Affichage

/// Valeur et format dans la barre, seuils orange et rouge.
private struct DisplaySection: View {
    let model: UsageModel

    var body: some View {
        @Bindable var settings = model.settings
        SettingsSection(title: "Affichage", spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                labeled("Valeur dans la barre") {
                    SegmentedControl(
                        options: displayOptions, selection: $settings.display,
                        height: 26, fills: true, label: "Valeur dans la barre")
                }
                labeled("Format") {
                    SegmentedControl(
                        options: ValueMode.allCases.map { ($0, $0.title) }, selection: $settings.valueMode,
                        height: 26, fills: true, label: "Format")
                }
            }
            HStack(alignment: .top, spacing: 24) {
                ThresholdSlider(
                    title: "Seuil orange", value: $settings.thresholds.warning,
                    range: 5...(settings.thresholds.critical - 5), color: PulseTheme.warning)
                .frame(maxWidth: .infinity)
                ThresholdSlider(
                    title: "Seuil rouge", value: $settings.thresholds.critical,
                    range: (settings.thresholds.warning + 5)...100, color: PulseTheme.critical)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
            SettingsNote("Les seuils portent sur le % utilisé, même si la barre affiche le restant.")
        }
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « Session », « Semaine »… d'après les limites de l'IA, quand elles
    /// sont connues.
    private var displayOptions: [(value: BarDisplay, title: String)] {
        let labels = model.windows.map { Self.shortLabel($0.label) }
        return [
            (.first, labels.first ?? "1re limite"),
            (.second, labels.count > 1 ? labels[1] : "2e limite"),
            (.both, "Les deux"),
        ]
    }

    /// « Session (5 h) » → « Session ».
    private static func shortLabel(_ label: String) -> String {
        let short = label.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? label
        return short.isEmpty ? label : short
    }
}

// MARK: - Aperçu et actualisation

private struct PreviewSection: View {
    let app: AppModel
    @Bindable var model: UsageModel

    /// Valeurs d'exemple tant que l'IA n'a rien renvoyé (celles de la maquette).
    private static let sample = [
        UsageWindow(label: "Session", percent: 78, resetsAt: nil, projectedFullAt: nil),
        UsageWindow(label: "Semaine", percent: 41, resetsAt: nil, projectedFullAt: nil),
    ]

    var body: some View {
        SettingsSection(padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)) {
            HStack(spacing: 14) {
                Text("Aperçu").font(.system(size: 13))
                chip
                    .help(model.windows.isEmpty ? "Valeurs d'exemple" : "Valeurs actuelles")
                Spacer(minLength: 12)
                Text("Actualiser toutes les").font(.system(size: 13))
                PopupMenu(
                    options: ServiceSettings.intervals.map { ($0, UsageFormat.interval($0)) },
                    selection: $model.refreshInterval,
                    label: "Actualiser toutes les")
            }
        }
    }

    /// La puce sur fond noir, dans le style choisi pour la barre des menus.
    private var chip: some View {
        let palette = BarPalette(isDark: true)
        let entry = previewEntry
        return Group {
            if app.menuBar.style == .rings {
                RingEntryView(entry: entry, palette: palette)
            } else {
                LogoPercentEntryView(entry: entry, palette: palette)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 6))
    }

    private var previewEntry: BarEntry {
        let settings = model.settings
        let windows = model.windows.isEmpty ? Self.sample : model.windows
        let content = UsageModel.barContent(windows: windows, settings: settings)
        let shown = settings.display.select(windows)
        return BarEntry(
            kind: model.service.logoKind,
            title: model.service.title,
            text: content.text,
            ringPercent: shown.map(\.percent).max().map(settings.valueMode.value(forUsed:)),
            level: content.level)
    }
}
