import Observation
import PulseCore

/// Tous les services suivis par l'app.
@MainActor
@Observable
final class AppModel {
    let claudeAccount: ClaudeAccount
    let claude: UsageModel
    let chatgpt: UsageModel
    let gemini: UsageModel
    let copilot: UsageModel
    let launchAtLogin = LaunchAtLogin()
    let alertCenter = AlertCenter()

    /// Dans l'ordre de la barre des menus et des onglets des réglages.
    var services: [UsageModel] { [claude, chatgpt, gemini, copilot] }

    /// Aucune puce dans la barre : l'icône de Pulse prend le relais.
    var noServiceShown: Bool { !services.contains(where: \.isEnabled) }

    init() {
        let monitor = AiMonitor()
        let claudeAccount = ClaudeAccount()
        self.claudeAccount = claudeAccount
        claude = UsageModel(service: .claude) {
            await claudeAccount.fetchState(monitor: monitor)
        }
        chatgpt = UsageModel(service: .chatGpt) {
            await Task.detached(priority: .utility) { monitor.refreshChatgpt() }.value
        }
        gemini = UsageModel(service: .gemini) {
            await Task.detached(priority: .utility) { monitor.refreshGemini() }.value
        }
        copilot = UsageModel(service: .copilot) {
            await Task.detached(priority: .utility) { monitor.refreshCopilot() }.value
        }
        for model in services {
            model.onNewState = { [alertCenter] service, state in
                alertCenter.handle(service: service, state: state)
            }
        }
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
}
