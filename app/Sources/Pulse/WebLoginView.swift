import SwiftUI
import WebKit

/// Une page de connexion (claude.ai, chatgpt.com) dans une fenêtre de Pulse.
/// Rien n'est enregistré sur le disque (data store non persistant) : on ne
/// garde que le cookie de session, que l'app range dans le Trousseau.
struct WebLoginView: NSViewRepresentable {
    let url: URL
    /// Domaine des cookies à surveiller, par ex. « claude.ai ».
    let domain: String
    /// Le secret à garder, tiré des cookies du domaine, ou nil s'il n'est pas
    /// encore là (l'utilisateur ne s'est pas encore connecté).
    let extract: @MainActor ([HTTPCookie]) -> String?
    let onLogin: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(domain: domain, extract: extract, onLogin: onLogin)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.watchCookies(of: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private let domain: String
        private let extract: @MainActor ([HTTPCookie]) -> String?
        private let onLogin: @MainActor (String) -> Void
        private var watchTask: Task<Void, Never>?

        init(domain: String, extract: @escaping @MainActor ([HTTPCookie]) -> String?,
             onLogin: @escaping @MainActor (String) -> Void) {
            self.domain = domain
            self.extract = extract
            self.onLogin = onLogin
        }

        /// Regarde les cookies chaque seconde jusqu'à trouver la session. La
        /// notification de changement de WebKit ne suffit pas : elle ne se
        /// déclenche pas toujours.
        func watchCookies(of webView: WKWebView) {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            watchTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let cookies = await cookieStore.allCookies().filter { self.isInDomain($0.domain) }
                    if let secret = self.extract(cookies) {
                        self.onLogin(secret)
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        func stop() {
            watchTask?.cancel()
        }

        private func isInDomain(_ cookieDomain: String) -> Bool {
            let host = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
            return host == domain || host.hasSuffix(".\(domain)")
        }
    }
}

extension WebLoginView {
    /// claude.ai : le cookie « sessionKey ».
    static func claude(onLogin: @escaping @MainActor (String) -> Void) -> WebLoginView {
        WebLoginView(url: URL(string: "https://claude.ai/login")!, domain: "claude.ai", extract: { cookies in
            cookies.first { $0.name == "sessionKey" && !$0.value.isEmpty }?.value
        }, onLogin: onLogin)
    }

    /// chatgpt.com : le cookie de session, parfois découpé en plusieurs
    /// morceaux (« …session-token.0 », « .1 »). On garde l'en-tête Cookie complet.
    static func chatGpt(onLogin: @escaping @MainActor (String) -> Void) -> WebLoginView {
        WebLoginView(url: URL(string: "https://chatgpt.com/auth/login")!, domain: "chatgpt.com", extract: { cookies in
            let session = cookies
                .filter { $0.name.hasPrefix("__Secure-next-auth.session-token") && !$0.value.isEmpty }
                .sorted { $0.name < $1.name }
            guard !session.isEmpty else { return nil }
            return session.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }, onLogin: onLogin)
    }
}
