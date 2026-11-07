import SwiftUI

struct SettingsView: View {
    let app: AppModel

    @AppStorage(ClaudeAuthMethod.storageKey) private var method = ClaudeAuthMethod.claudeCode
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Claude") {
                Picker("Connexion", selection: $method) {
                    ForEach(ClaudeAuthMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }

                if method == .claudeAi {
                    if app.claudeAccount.claudeAiConnected {
                        LabeledContent("Compte claude.ai", value: "connecté")
                        Button("Se déconnecter") {
                            app.disconnectClaudeAi()
                        }
                    } else {
                        Button("Se connecter à claude.ai…") {
                            openWindow(id: WindowID.claudeLogin)
                            NSApp.activate()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        .onChange(of: method) {
            app.claude.refreshNow()
        }
    }
}
