import AppKit
import SwiftUI

/// Les fenêtres de Pulse.
enum WindowID {
    static let settings = "settings"
    static let claudeLogin = "claude-login"
    static let chatGptLogin = "chatgpt-login"
    static let githubLogin = "github-login"
    static let update = "update"
}

/// Ouvre et ferme les fenêtres de Pulse. Les puces de la barre des menus
/// sont gérées par AppKit (NSStatusItem), sans vue SwiftUI toujours présente
/// pour utiliser `openWindow` : ce routeur s'en charge à leur place.
@MainActor
final class WindowRouter: NSObject, NSWindowDelegate {
    static let shared = WindowRouter()

    /// Branché au lancement (voir AppDelegate).
    var app: AppModel?
    private var windows: [String: NSWindow] = [:]

    /// Ouvre la fenêtre Réglages au premier plan, sur l'onglet demandé.
    func showSettings(tab: String) {
        UserDefaults.standard.set(tab, forKey: SettingsTab.storageKey)
        show(WindowID.settings)
    }

    func show(_ id: String) {
        guard let app else { return }
        let window = windows[id] ?? makeWindow(id, app: app)
        windows[id] = window
        // L'app n'a pas d'icône dans le Dock : il faut l'activer pour que la
        // fenêtre passe au premier plan.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ id: String) {
        windows[id]?.close()
    }

    // MARK: - Fenêtres

    private func makeWindow(_ id: String, app: AppModel) -> NSWindow {
        let (title, content, size, resizable): (String, AnyView, NSSize?, Bool) = switch id {
        case WindowID.update:
            ("Mise à jour de Pulse", AnyView(UpdateWindow(updater: app.updater)), nil, false)
        case WindowID.claudeLogin:
            ("Connexion à claude.ai", AnyView(WebLoginView.claude { sessionKey in
                app.connectClaudeAi(sessionKey: sessionKey)
                WindowRouter.shared.close(WindowID.claudeLogin)
            }), NSSize(width: 520, height: 720), true)
        case WindowID.chatGptLogin:
            ("Connexion à ChatGPT", AnyView(WebLoginView.chatGpt { cookie in
                app.connectAccount(.chatGpt, secret: cookie)
                WindowRouter.shared.close(WindowID.chatGptLogin)
            }), NSSize(width: 520, height: 720), true)
        case WindowID.githubLogin:
            ("Connexion à GitHub", AnyView(GitHubLoginView(monitor: app.monitor) { token in
                app.connectAccount(.copilot, secret: token)
                WindowRouter.shared.close(WindowID.githubLogin)
            }), nil, false)
        default:
            ("Réglages", AnyView(SettingsView(app: app)), NSSize(width: 780, height: 540), true)
        }

        let controller = NSHostingController(rootView: content)
        if size == nil {
            // La fenêtre prend la taille de son contenu SwiftUI.
            controller.sizingOptions = .preferredContentSize
        }
        let window = NSWindow(contentViewController: controller)
        window.title = title
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { styleMask.insert(.resizable) }
        window.styleMask = styleMask
        if let size {
            window.setContentSize(size)
            window.contentMinSize = NSSize(width: 420, height: 560)
        }
        if id == WindowID.settings {
            // Comme la maquette : thème sombre, barre de titre transparente,
            // les boutons de la fenêtre posés sur la barre latérale.
            controller.sceneBridgingOptions = []
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(red: 0x1E / 255, green: 0x1E / 255, blue: 0x20 / 255, alpha: 1)
            window.contentMinSize = NSSize(width: 780, height: 540)
            // La barre de titre fait maintenant partie du contenu : 540 en tout.
            window.setContentSize(NSSize(width: 780, height: 540))
        }
        if id == WindowID.update {
            // Au-dessus des autres fenêtres : à l'ouverture de session, d'autres
            // apps se lancent en même temps et la cacheraient sinon.
            window.level = .floating
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Une fenêtre fermée est oubliée : elle repartira de zéro à la prochaine
    /// ouverture (par ex. une page de connexion vierge).
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }
}
