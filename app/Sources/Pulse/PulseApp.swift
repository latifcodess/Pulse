import SwiftUI

enum WindowID {
    static let settings = "settings"
    static let claudeLogin = "claude-login"
    static let update = "update"
}

@main
struct PulseApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        // Une puce par IA suivie dans la barre des menus, chacune avec son popover.
        ServiceMenuBarItem(model: app.claude, alerts: app.alertCenter, updater: app.updater)
        ServiceMenuBarItem(model: app.chatgpt, alerts: app.alertCenter, updater: app.updater)
        ServiceMenuBarItem(model: app.gemini, alerts: app.alertCenter, updater: app.updater)
        ServiceMenuBarItem(model: app.copilot, alerts: app.alertCenter, updater: app.updater)

        // Si aucune IA n'est suivie, cette icône garde un accès aux réglages.
        MenuBarExtra(isInserted: Binding(get: { app.noServiceShown }, set: { _ in })) {
            FallbackMenu(updater: app.updater)
        } label: {
            Image(systemName: "waveform.path.ecg")
                .opensWindowsOnRequest(alerts: app.alertCenter, updater: app.updater)
        }

        Window("Réglages", id: WindowID.settings) {
            SettingsView(app: app)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Mise à jour de Pulse", id: WindowID.update) {
            UpdateWindow(updater: app.updater)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        // Au-dessus des autres fenêtres : à l'ouverture de session, d'autres
        // apps se lancent en même temps et la cacheraient sinon.
        .windowLevel(.floating)
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
    let updater: Updater

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { model.isEnabled }, set: { model.isEnabled = $0 })) {
            PopoverContent(model: model, updater: updater)
        } label: {
            let bar = model.bar
            MenuBarLabel(logo: model.service.logo(), text: bar.text, level: bar.level)
                .opensWindowsOnRequest(alerts: alerts, updater: updater)
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

/// Ouvre la fenêtre de mise à jour au premier plan.
@MainActor
private func showUpdateWindow(openWindow: OpenWindowAction) {
    openWindow(id: WindowID.update)
    NSApp.activate()
}

/// Ouvre une fenêtre quand on la demande hors d'une vue : clic sur une
/// notification, ou mise à jour trouvée au lancement. Les puces de la barre
/// des menus sont les seules vues toujours présentes : ce sont elles qui
/// écoutent.
private struct OpensWindowsOnRequest: ViewModifier {
    let alerts: AlertCenter
    let updater: Updater
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: alerts.settingsRequest) { _, request in
                guard let request else { return }
                if request.tab == AlertCenter.updateWindowTab {
                    showUpdateWindow(openWindow: openWindow)
                } else {
                    showSettings(tab: request.tab, openWindow: openWindow)
                }
            }
            .onChange(of: updater.windowRequest) { _, request in
                if request != nil {
                    showUpdateWindow(openWindow: openWindow)
                }
            }
    }
}

extension View {
    fileprivate func opensWindowsOnRequest(alerts: AlertCenter, updater: Updater) -> some View {
        modifier(OpensWindowsOnRequest(alerts: alerts, updater: updater))
    }
}

private struct FallbackMenu: View {
    let updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Aucune IA suivie")
        Button("Réglages…") {
            showSettings(tab: SettingsTab.general, openWindow: openWindow)
        }
        .keyboardShortcut(",")
        Button("Rechercher les mises à jour…") {
            showUpdateWindow(openWindow: openWindow)
            Task { await updater.check(.user) }
        }
        Divider()
        Button("Quitter Pulse") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct PopoverContent: View {
    let model: UsageModel
    let updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        UsagePopover(
            state: model.state,
            service: model.service,
            lastUpdated: model.lastUpdated,
            thresholds: model.settings.thresholds,
            refreshInterval: model.refreshInterval,
            isRefreshing: model.isRefreshing,
            updateVersion: updater.availableUpdate?.version,
            onRefresh: { model.refreshNow() },
            onSettings: { showSettings(tab: model.service.storageKey, openWindow: openWindow) },
            onUpdate: { showUpdateWindow(openWindow: openWindow) },
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
