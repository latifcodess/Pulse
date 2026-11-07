import Foundation
import PulseCore
import WebKit

/// Repli quand claude.ai bloque les requêtes directes : une page claude.ai
/// invisible fait les requêtes elle-même, comme un vrai navigateur.
@MainActor
enum ClaudeWebFallback {
    private static let loadTimeout: Duration = .seconds(20)

    static func fetchState(sessionKey: String, monitor: AiMonitor) async -> AiState {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)

        guard
            let cookie = HTTPCookie(properties: [
                .domain: ".claude.ai",
                .path: "/",
                .name: "sessionKey",
                .value: sessionKey,
                .secure: "TRUE",
            ])
        else {
            return .unavailable
        }
        await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)

        let loader = PageLoader()
        guard await loader.load(URL(string: "https://claude.ai/")!, in: webView, timeout: loadTimeout),
            let organizations = await fetch("/api/organizations", in: webView)
        else {
            return .blocked
        }
        guard let usagePath = claudeWebUsagePath(organizations: organizations) else {
            // Rust classe la réponse : page anti-bot, session expirée, etc.
            return monitor.claudeStateFromWebResponse(response: organizations)
        }
        guard let usage = await fetch(usagePath, in: webView) else {
            return .blocked
        }
        return monitor.claudeStateFromWebResponse(response: usage)
    }

    private struct PageResponse: Decodable {
        let status: Int
        let contentType: String?
        let body: String
    }

    /// fetch() en JavaScript, depuis la page claude.ai déjà chargée.
    private static func fetch(_ path: String, in webView: WKWebView) async -> HttpResponse? {
        let script = """
            const response = await fetch(path, {
                headers: { Accept: "application/json" },
                credentials: "include",
                signal: AbortSignal.timeout(10000),
            });
            return JSON.stringify({
                status: response.status,
                contentType: response.headers.get("content-type"),
                body: await response.text(),
            });
            """
        guard
            let json = try? await webView.callAsyncJavaScript(
                script, arguments: ["path": path], contentWorld: .defaultClient) as? String,
            let page = try? JSONDecoder().decode(PageResponse.self, from: Data(json.utf8))
        else {
            return nil
        }
        return HttpResponse(status: UInt16(clamping: page.status), contentType: page.contentType, body: page.body)
    }
}

/// Attend la fin du chargement d'une page, avec un délai maximum.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func load(_ url: URL, in webView: WKWebView, timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.load(URLRequest(url: url))
            Task {
                try? await Task.sleep(for: timeout)
                self.finish(false)
            }
        }
    }

    /// Ne répond qu'une fois : au chargement, à l'échec ou au délai dépassé.
    private func finish(_ loaded: Bool) {
        continuation?.resume(returning: loaded)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(false)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        finish(false)
    }
}
