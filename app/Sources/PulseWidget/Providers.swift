import WidgetKit

/// Une image du widget à un instant donné.
struct PulseEntry: TimelineEntry {
    let date: Date
    /// nil : Pulse n'a encore rien écrit (ou le fichier est illisible).
    let snapshot: WidgetSnapshot?
    /// L'IA choisie (petit et grand widgets).
    var serviceID: String?

    var service: WidgetSnapshot.Service? {
        snapshot?.services.first { $0.id == serviceID }
    }
}

extension PulseEntry {
    /// Une entrée toutes les 5 min pendant une heure : « il y a X min » et le
    /// grisé restent à jour entre deux actualisations de l'app, qui de toute
    /// façon redemande un rafraîchissement après chacune.
    static func timeline(serviceID: String?) -> Timeline<PulseEntry> {
        let snapshot = WidgetSnapshot.read()
        let now = Date.now
        let entries = (0...12).map { step in
            PulseEntry(date: now.addingTimeInterval(TimeInterval(step * 5 * 60)), snapshot: snapshot, serviceID: serviceID)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600)))
    }

    static func now(serviceID: String?) -> PulseEntry {
        PulseEntry(date: .now, snapshot: WidgetSnapshot.read(), serviceID: serviceID)
    }

    /// Les valeurs de la maquette, pour la galerie des widgets.
    static func placeholder(serviceID: String?) -> PulseEntry {
        let now = Date.now
        let hour: TimeInterval = 3600
        // La session de Claude monte depuis 3 h : 100 % vers +1 h 30, reset à +2 h.
        let history = stride(from: -3 * hour, through: 0, by: hour / 4).map { offset in
            WidgetSnapshot.Point(date: now.addingTimeInterval(offset), percent: 78 * pow((offset + 3 * hour) / (3 * hour), 1.4))
        }
        func window(_ label: String, _ percent: Double, reset: TimeInterval, full: TimeInterval? = nil,
                    history: [WidgetSnapshot.Point]? = nil) -> WidgetSnapshot.Window {
            WidgetSnapshot.Window(
                label: label, percent: percent, resetsAt: now.addingTimeInterval(reset),
                projectedFullAt: full.map(now.addingTimeInterval), history: history)
        }
        func service(_ id: String, _ title: String, _ windows: [WidgetSnapshot.Window]) -> WidgetSnapshot.Service {
            WidgetSnapshot.Service(
                id: id, title: title, followed: true, state: .ok, updatedAt: now, warning: 75, critical: 90,
                windows: windows)
        }
        let snapshot = WidgetSnapshot(writtenAt: now, services: [
            service("claude", "Claude", [
                window("Session (5 h)", 78, reset: 2 * hour, full: 1.5 * hour, history: history),
                window("Semaine", 41, reset: 4 * 86400),
            ]),
            service("chatgpt", "ChatGPT", [window("Session (5 h)", 42, reset: 3 * hour)]),
            service("gemini", "Gemini", [window("Jour", 12, reset: 20 * hour)]),
            service("copilot", "Copilot", [window("Mois", 63, reset: 12 * 86400)]),
        ])
        return PulseEntry(date: now, snapshot: snapshot, serviceID: serviceID)
    }
}

struct SingleServiceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        .placeholder(serviceID: "claude")
    }

    func snapshot(for configuration: SelectServiceIntent, in context: Context) async -> PulseEntry {
        context.isPreview ? .placeholder(serviceID: configuration.service.rawValue)
            : .now(serviceID: configuration.service.rawValue)
    }

    func timeline(for configuration: SelectServiceIntent, in context: Context) async -> Timeline<PulseEntry> {
        PulseEntry.timeline(serviceID: configuration.service.rawValue)
    }
}

struct AllServicesProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        .placeholder(serviceID: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(context.isPreview ? .placeholder(serviceID: nil) : .now(serviceID: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        completion(PulseEntry.timeline(serviceID: nil))
    }
}
