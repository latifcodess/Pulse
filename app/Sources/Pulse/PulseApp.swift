import AppKit
import SwiftUI

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // La barre des menus et les fenêtres sont gérées par AppKit
        // (StatusBarController, WindowRouter) : SwiftUI n'a pas de scène à afficher.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var app: AppModel?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = AppModel()
        self.app = app
        WindowRouter.shared.app = app
        statusBar = StatusBarController(app: app)
    }

    /// Un clic sur le widget : « pulse://ia/claude » ouvre la fenêtre de Claude.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let id = urls.lazy.compactMap(PulseLink.serviceID(from:)).first,
            let service = app?.services.first(where: { $0.service.storageKey == id })?.service
        else { return }
        Task { @MainActor in
            // Au lancement par le lien, les éléments de la barre viennent
            // d'apparaître : on leur laisse le temps d'être placés.
            try? await Task.sleep(for: .milliseconds(400))
            statusBar?.showDetail(for: service)
        }
    }
}

