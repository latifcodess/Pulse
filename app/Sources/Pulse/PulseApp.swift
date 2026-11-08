import SwiftUI

enum WindowID {
    static let settings = "settings"
    static let claudeLogin = "claude-login"
}

@main
struct PulseApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        // Une puce par IA dans la barre des menus, chacune avec son popover.
        MenuBarExtra {
            PopoverContent(model: app.claude)
        } label: {
            ServiceLabel(model: app.claude)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra {
            PopoverContent(model: app.chatgpt)
        } label: {
            ServiceLabel(model: app.chatgpt)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra {
            PopoverContent(model: app.copilot)
        } label: {
            ServiceLabel(model: app.copilot)
        }
        .menuBarExtraStyle(.window)

        Window("Réglages", id: WindowID.settings) {
            SettingsView(app: app)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Connexion à claude.ai", id: WindowID.claudeLogin) {
            ClaudeLoginWindow(app: app)
        }
        .defaultSize(width: 520, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

private struct ServiceLabel: View {
    let model: UsageModel

    var body: some View {
        MenuBarLabel(symbol: model.service.symbol, text: model.barText, level: model.barLevel)
    }
}

private struct PopoverContent: View {
    let model: UsageModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        UsagePopover(
            state: model.state,
            service: model.service,
            lastUpdated: model.lastUpdated,
            isRefreshing: model.isRefreshing,
            onRefresh: { model.refreshNow() },
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
    let app: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ClaudeLoginView { sessionKey in
            app.connectClaudeAi(sessionKey: sessionKey)
            dismissWindow(id: WindowID.claudeLogin)
        }
        .frame(minWidth: 420, minHeight: 560)
    }
}
