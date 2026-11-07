import SwiftUI

struct SettingsView: View {
    let usage: UsageModel

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
                    if usage.claudeAiConnected {
                        LabeledContent("Compte claude.ai", value: "connecté")
                        Button("Se déconnecter") {
                            usage.disconnectClaudeAi()
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
            usage.refreshNow()
        }
    }
}
