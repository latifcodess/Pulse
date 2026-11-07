import SwiftUI

enum WindowID {
    static let settings = "settings"
    static let claudeLogin = "claude-login"
}

@main
struct PulseApp: App {
    @State private var usage = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text(usage.sessionText)
            }
        }

        Window("Réglages", id: WindowID.settings) {
            SettingsView(usage: usage)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Connexion à claude.ai", id: WindowID.claudeLogin) {
            ClaudeLoginWindow(usage: usage)
        }
        .defaultSize(width: 520, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Réglages…") {
            openWindow(id: WindowID.settings)
            // L'app n'a pas d'icône dans le Dock : il faut l'activer pour que
            // la fenêtre passe au premier plan.
            NSApp.activate()
        }
        Divider()
        Button("Quitter") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct ClaudeLoginWindow: View {
    let usage: UsageModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ClaudeLoginView { sessionKey in
            usage.connectClaudeAi(sessionKey: sessionKey)
            dismissWindow(id: WindowID.claudeLogin)
        }
        .frame(minWidth: 420, minHeight: 560)
    }
}
