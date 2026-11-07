import Observation
import PulseCore

/// Tous les services suivis par l'app.
@MainActor
@Observable
final class AppModel {
    let claudeAccount: ClaudeAccount
    let claude: UsageModel
    let chatgpt: UsageModel

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
