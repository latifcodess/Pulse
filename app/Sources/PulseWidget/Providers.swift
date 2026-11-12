import WidgetKit

/// Une image du widget à un instant donné.
struct PulseEntry: TimelineEntry {
    let date: Date
    /// nil : Pulse n'a encore rien écrit (ou le fichier est illisible).
    let snapshot: WidgetSnapshot?
    /// L'IA choisie (petit widget seulement).
    var serviceID: String?
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

    /// Données d'exemple, pour la galerie des widgets.
    static func placeholder(serviceID: String?) -> PulseEntry {
        let now = Date.now
        func service(_ id: String, _ title: String, _ percents: [Double]) -> WidgetSnapshot.Service {
            WidgetSnapshot.Service(
                id: id, title: title, followed: true, state: .ok, updatedAt: now, warning: 75, critical: 90,
                windows: percents.enumerated().map { index, percent in
                    WidgetSnapshot.Window(
                        label: index == 0 ? "Session" : "Semaine", percent: percent,
                        resetsAt: now.addingTimeInterval(index == 0 ? 2 * 3600 : 4 * 86400), projectedFullAt: nil)
                })
        }
        let snapshot = WidgetSnapshot(writtenAt: now, services: [
            service("claude", "Claude", [42, 18]),
            service("chatgpt", "ChatGPT", [77, 30]),
            service("gemini", "Gemini", [12]),
            service("copilot", "Copilot", [93]),
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
