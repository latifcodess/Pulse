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
            PopoverContent(usage: usage)
        } label: {
            MenuBarLabel(text: usage.sessionText, level: usage.sessionLevel)
        }
        .menuBarExtraStyle(.window)

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

private struct PopoverContent: View {
    let usage: UsageModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        UsagePopover(
            state: usage.state,
            method: usage.method,
            lastUpdated: usage.lastUpdated,
            isRefreshing: usage.isRefreshing,
            onRefresh: { usage.refreshNow() },
            onSettings: {
                openWindow(id: WindowID.settings)
                // L'app n'a pas d'icône dans le Dock : il faut l'activer pour que
                // la fenêtre passe au premier plan.
                NSApp.activate()
            },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
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
