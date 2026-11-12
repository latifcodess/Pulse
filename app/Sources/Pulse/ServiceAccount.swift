import Foundation
import Observation
import PulseCore

/// Comment Pulse se connecte à ChatGPT, Gemini ou Copilot : avec l'outil en
/// ligne de commande (lu, jamais modifié), ou avec un compte connecté dans
/// Pulse. Ce choix n'est pas un secret : il est rangé dans les préférences.
enum ConnectionMethod: String, CaseIterable, Identifiable {
    case cli
    case account

    var id: Self { self }

    static func storageKey(for service: AiService) -> String {
        "\(service.storageKey).connection"
    }

    static func current(for service: AiService) -> ConnectionMethod {
        UserDefaults.standard.string(forKey: storageKey(for: service)).flatMap(Self.init(rawValue:)) ?? .cli
    }
}

/// Un compte connecté dans Pulse. Son secret (cookie ou token) est dans le
/// Trousseau ; l'app ne le garde pas en mémoire.
@MainActor
@Observable
final class ServiceAccount {
    let service: AiService
    private(set) var isConnected = false
    @ObservationIgnored private let secret: KeychainSecret

    init(service: AiService, secret: KeychainSecret) {
        self.service = service
        self.secret = secret
    }

    /// Lit le secret hors du thread principal (le Trousseau peut demander une
    /// autorisation), et met à jour `isConnected`.
    func readSecret() async -> String? {
        let secret = secret
        let value = await Task.detached(priority: .utility) { secret.read() }.value
        isConnected = value != nil
        return value
    }

    func connect(_ value: String) async {
        let secret = secret
        isConnected = await Task.detached { secret.save(value) }.value
    }

    func disconnect() async {
        let secret = secret
        _ = await Task.detached { secret.delete() }.value
        isConnected = false
    }
}
