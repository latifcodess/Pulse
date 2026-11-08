import SwiftUI

enum WindowID {
    static let settings = "settings"
    static let claudeLogin = "claude-login"
}

@main
struct PulseApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        // Une puce par IA suivie dans la barre des menus, chacune avec son popover.
        ServiceMenuBarItem(model: app.claude, alerts: app.alertCenter)
        ServiceMenuBarItem(model: app.chatgpt, alerts: app.alertCenter)
        ServiceMenuBarItem(model: app.gemini, alerts: app.alertCenter)
        ServiceMenuBarItem(model: app.copilot, alerts: app.alertCenter)

        // Si aucune IA n'est suivie, cette icône garde un accès aux réglages.
        MenuBarExtra(isInserted: Binding(get: { app.noServiceShown }, set: { _ in })) {
            FallbackMenu()
        } label: {
            Image(systemName: "waveform.path.ecg")
                .opensSettingsOnRequest(from: app.alertCenter)
        }

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

/// La puce d'une IA. Elle disparaît quand l'IA n'est plus suivie ; si
/// l'utilisateur la retire de la barre (⌘-glisser), l'IA n'est plus suivie.
private struct ServiceMenuBarItem: Scene {
    let model: UsageModel
    let alerts: AlertCenter

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { model.isEnabled }, set: { model.isEnabled = $0 })) {
            PopoverContent(model: model)
        } label: {
            let bar = model.bar
            MenuBarLabel(symbol: model.service.symbol, text: bar.text, level: bar.level)
                .opensSettingsOnRequest(from: alerts)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ouvre la fenêtre Réglages au premier plan, sur l'onglet demandé.
@MainActor
private func showSettings(tab: String, openWindow: OpenWindowAction) {
    UserDefaults.standard.set(tab, forKey: SettingsTab.storageKey)
    openWindow(id: WindowID.settings)
    // L'app n'a pas d'icône dans le Dock : il faut l'activer pour que la
    // fenêtre passe au premier plan.
    NSApp.activate()
}

/// Ouvre les réglages quand un clic sur une notification le demande. Les
/// puces de la barre des menus sont les seules vues toujours présentes : ce
/// sont elles qui écoutent.
private struct OpensSettingsOnRequest: ViewModifier {
    let alerts: AlertCenter
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: alerts.settingsRequest) { _, request in
            if let request {
                showSettings(tab: request.tab, openWindow: openWindow)
            }
        }
    }
}

extension View {
    fileprivate func opensSettingsOnRequest(from alerts: AlertCenter) -> some View {
        modifier(OpensSettingsOnRequest(alerts: alerts))
    }
}

private struct FallbackMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Aucune IA suivie")
        Button("Réglages…") {
            showSettings(tab: SettingsTab.general, openWindow: openWindow)
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quitter Pulse") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
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
            thresholds: model.settings.thresholds,
            refreshInterval: model.refreshInterval,
            isRefreshing: model.isRefreshing,
            onRefresh: { model.refreshNow() },
            onSettings: { showSettings(tab: model.service.storageKey, openWindow: openWindow) },
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
