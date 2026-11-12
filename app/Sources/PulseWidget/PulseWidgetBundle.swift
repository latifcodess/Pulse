import SwiftUI
import WidgetKit

/// Les widgets de Pulse : une IA (petit), ou toutes les IA suivies (moyen).
@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleServiceWidget()
        AllServicesWidget()
    }
}

struct SingleServiceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PulseSingleService", intent: SelectServiceIntent.self, provider: SingleServiceProvider()) {
            entry in
            SingleServiceView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Pulse — une IA")
        .description("Les limites d'une IA, avec l'heure de réinitialisation.")
        .supportedFamilies([.systemSmall])
    }
}

struct AllServicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseAllServices", provider: AllServicesProvider()) { entry in
            AllServicesView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Pulse — toutes les IA")
        .description("Les IA suivies dans Pulse, d'un coup d'œil.")
        .supportedFamilies([.systemMedium])
    }
}
