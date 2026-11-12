import Foundation

/// Ce que l'app partage avec le widget : un fichier JSON dans le conteneur de
/// l'App Group. Le widget ne lit que ce fichier (ni réseau, ni Trousseau).
/// Ce fichier est compilé à la fois dans l'app et dans le widget.
struct WidgetSnapshot: Codable, Sendable {
    /// Quand l'app a écrit le fichier.
    var writtenAt: Date
    var services: [Service]

    struct Service: Codable, Sendable, Identifiable {
        /// « claude », « chatgpt », « gemini », « copilot ».
        var id: String
        var title: String
        /// L'IA est suivie dans les réglages de Pulse.
        var followed: Bool
        var state: State
        /// Heure de la dernière réponse valide.
        var updatedAt: Date?
        /// Seuils de couleur (orange, rouge), en % utilisé.
        var warning: Int
        var critical: Int
        var windows: [Window]
    }

    enum State: String, Codable, Sendable {
        case loading, ok, offline, notConnected, expired, blocked, unavailable
    }

    struct Window: Codable, Sendable {
        var label: String
        /// % utilisé, entre 0 et 100.
        var percent: Double
        var resetsAt: Date?
        var projectedFullAt: Date?
    }
}

extension WidgetSnapshot {
    /// L'App Group, préfixé par le Team ID (« 79W4JUNG7Y.ch.latifcodess.pulse ») :
    /// le nom complet est écrit dans l'Info.plist au moment du build.
    static var appGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "PulseAppGroup") as? String
    }
    /// Au-delà, les données sont affichées en grisé.
    static let staleAfter: TimeInterval = 15 * 60

    static var fileURL: URL? {
        guard let appGroup else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget.json")
    }

    /// nil si le fichier manque ou est illisible : le widget affiche alors
    /// une invitation à ouvrir Pulse, jamais un crash.
    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func write() throws {
        guard let url = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension WidgetSnapshot.Service {
    /// Les données ont plus de 15 min (ou il n'y en a jamais eu de valide).
    func isStale(at now: Date) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > WidgetSnapshot.staleAfter
    }
}
