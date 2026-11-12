import AppKit
import Observation
import PulseCore

/// Connexion au compte Google pour Gemini. Google refuse les fenêtres web
/// intégrées : la page de connexion s'ouvre dans le navigateur, et Pulse
/// attend la réponse sur une adresse locale (voir gemini.rs).
@MainActor
@Observable
final class GoogleSignIn {
    enum Phase {
        case idle
        /// La page de Google est ouverte dans le navigateur.
        case waiting
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    @ObservationIgnored private var login: GeminiLogin?
    @ObservationIgnored private var cancelledByUser = false

    /// Ouvre la page de Google, attend la réponse (5 min au plus), puis donne
    /// le refresh_token à `onToken`.
    func start(onToken: @escaping @MainActor (String) async -> Void) async {
        if case .waiting = phase { return }
        guard let login = await Task.detached(operation: { geminiLoginStart() }).value,
            let url = URL(string: login.authorizationUrl())
        else {
            phase = .failed("Impossible de préparer la connexion. Réessayez.")
            return
        }
        self.login = login
        cancelledByUser = false
        phase = .waiting
        NSWorkspace.shared.open(url)

        let result = await Task.detached(priority: .utility) { login.wait(timeoutSeconds: 300) }.value
        self.login = nil
        switch result {
        case .success(let refreshToken):
            await onToken(refreshToken)
            phase = .idle
        case .denied:
            phase = .failed("La connexion a été refusée sur la page de Google.")
        case .cancelled:
            phase = cancelledByUser ? .idle : .failed("Délai dépassé. Recommencez la connexion.")
        case .failed:
            phase = .failed("La connexion a échoué. Réessayez.")
        }
    }

    func cancel() {
        cancelledByUser = true
        login?.cancel()
    }
}
