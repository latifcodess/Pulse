import OSLog
import SwiftUI
import WebKit

/// La page de connexion de claude.ai. Rien n'est enregistré sur le disque
/// (data store non persistant) : on ne garde que le cookie sessionKey.
struct ClaudeLoginView: NSViewRepresentable {
    let onSessionKey: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionKey: onSessionKey)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.watchCookies(of: webView)
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private let onSessionKey: (String) -> Void
        private var watchTask: Task<Void, Never>?
        private static let logger = Logger(subsystem: "ch.latifcodess.pulse", category: "claude-login")

        init(onSessionKey: @escaping (String) -> Void) {
            self.onSessionKey = onSessionKey
        }

        /// Regarde les cookies chaque seconde jusqu'à trouver sessionKey. La
        /// notification de changement de WebKit ne suffit pas : elle ne se
        /// déclenche pas toujours.
        func watchCookies(of webView: WKWebView) {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            watchTask = Task { [weak self] in
                var loggedNames: [String] = []
                while !Task.isCancelled {
                    let cookies = await cookieStore.allCookies().filter { Self.isClaudeDomain($0.domain) }

                    // Journal des noms et domaines uniquement, jamais des valeurs.
                    let names = cookies.map { "\($0.name)@\($0.domain)" }.sorted()
                    if names != loggedNames {
                        Self.logger.notice("Cookies claude.ai : \(names.joined(separator: ", "), privacy: .public)")
                        loggedNames = names
                    }

                    if let cookie = cookies.first(where: { $0.name == "sessionKey" && !$0.value.isEmpty }) {
                        Self.logger.notice("Cookie sessionKey trouvé")
                        self?.onSessionKey(cookie.value)
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        func stop() {
            watchTask?.cancel()
        }

        private static func isClaudeDomain(_ domain: String) -> Bool {
            let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            return host == "claude.ai" || host.hasSuffix(".claude.ai")
        }
    }
}
