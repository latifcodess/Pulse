import Observation
import PulseCore

/// Tous les services suivis par l'app.
@MainActor
@Observable
final class AppModel {
    let monitor: AiMonitor
    let claudeAccount: ClaudeAccount
    /// Comptes connectés dans Pulse (méthode « compte » au lieu de l'outil CLI).
    let chatgptAccount: ServiceAccount
    let geminiAccount: ServiceAccount
    let copilotAccount: ServiceAccount
    let googleSignIn = GoogleSignIn()
    let claude: UsageModel
    let chatgpt: UsageModel
    let gemini: UsageModel
    let copilot: UsageModel
    let launchAtLogin = LaunchAtLogin()
    let alertCenter = AlertCenter()
    let updater = Updater()
    let popovers = PopoverCoordinator()
    private let widgetExporter = WidgetExporter()

    /// Dans l'ordre de la barre des menus et des onglets des réglages.
    var services: [UsageModel] { [claude, chatgpt, gemini, copilot] }

    /// Aucune puce dans la barre : l'icône de Pulse prend le relais.
    var noServiceShown: Bool { !services.contains(where: \.isEnabled) }

    init() {
        let monitor = AiMonitor()
        self.monitor = monitor
        let claudeAccount = ClaudeAccount()
        self.claudeAccount = claudeAccount
        let chatgptAccount = ServiceAccount(service: .chatGpt, secret: .chatGptSession)
        let geminiAccount = ServiceAccount(service: .gemini, secret: .googleRefreshToken)
        let copilotAccount = ServiceAccount(service: .copilot, secret: .githubToken)
        self.chatgptAccount = chatgptAccount
        self.geminiAccount = geminiAccount
        self.copilotAccount = copilotAccount

        claude = UsageModel(service: .claude) {
            await claudeAccount.fetchState(monitor: monitor)
        }
        // Pour les autres IA : l'outil CLI, ou le compte connecté dans Pulse.
        chatgpt = UsageModel(service: .chatGpt) {
            switch ConnectionMethod.current(for: .chatGpt) {
            case .cli:
                return await Task.detached(priority: .utility) { monitor.refreshChatgpt() }.value
            case .account:
                guard let cookie = await chatgptAccount.readSecret() else { return .notConnected }
                return await Task.detached(priority: .utility) { monitor.refreshChatgptAccount(sessionCookie: cookie) }.value
            }
        }
        gemini = UsageModel(service: .gemini) {
            switch ConnectionMethod.current(for: .gemini) {
            case .cli:
                return await Task.detached(priority: .utility) { monitor.refreshGemini() }.value
            case .account:
                guard let token = await geminiAccount.readSecret() else { return .notConnected }
                return await Task.detached(priority: .utility) { monitor.refreshGeminiAccount(refreshToken: token) }.value
            }
        }
        copilot = UsageModel(service: .copilot) {
            switch ConnectionMethod.current(for: .copilot) {
            case .cli:
                return await Task.detached(priority: .utility) { monitor.refreshCopilot() }.value
            case .account:
                guard let token = await copilotAccount.readSecret() else { return .notConnected }
                return await Task.detached(priority: .utility) { monitor.refreshCopilotAccount(token: token) }.value
            }
        }
        for model in services {
            model.onNewState = { [alertCenter, weak self] service, state in
                alertCenter.handle(service: service, state: state)
                self?.exportForWidget()
            }
            model.onFollowChange = { [weak self] in
                self?.exportForWidget()
            }
        }
        updater.notify = { [alertCenter] title, body in
            alertCenter.notifyAboutUpdate(title: title, body: body)
        }
        updater.start()
    }

    /// Le fichier lu par le widget (voir WidgetExporter).
    private func exportForWidget() {
        widgetExporter.scheduleExport(of: services)
    }

    func connectClaudeAi(sessionKey: String) {
        Task {
            await claudeAccount.connect(sessionKey: sessionKey)
            claude.refreshNow()
        }
    }

    func disconnectClaudeAi() {
        Task {
            await claudeAccount.disconnect()
            claude.refreshNow()
        }
    }

    /// Le compte connecté dans Pulse pour cette IA (pas pour Claude, qui a le sien).
    func account(for service: AiService) -> ServiceAccount? {
        switch service {
        case .chatGpt: chatgptAccount
        case .gemini: geminiAccount
        case .copilot: copilotAccount
        case .claude: nil
        }
    }

    func model(for service: AiService) -> UsageModel {
        switch service {
        case .claude: claude
        case .chatGpt: chatgpt
        case .gemini: gemini
        case .copilot: copilot
        }
    }

    /// Range le secret du compte dans le Trousseau, puis actualise l'IA.
    func connectAccount(_ service: AiService, secret: String) {
        guard let account = account(for: service) else { return }
        Task {
            await account.connect(secret)
            model(for: service).refreshNow()
        }
    }

    func disconnectAccount(_ service: AiService) {
        guard let account = account(for: service) else { return }
        Task {
            await account.disconnect()
            model(for: service).refreshNow()
        }
    }

    /// Connexion Google pour Gemini, dans le navigateur.
    func signInWithGoogle() {
        Task {
            // AppModel vit aussi longtemps que l'app : pas besoin de « weak ».
            await googleSignIn.start { refreshToken in
                self.connectAccount(.gemini, secret: refreshToken)
            }
        }
    }
}
