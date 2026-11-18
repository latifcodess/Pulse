import SwiftUI
import WidgetKit

/// Les widgets de Pulse : une IA au choix (petit et grand), ou les 4 IA (moyen).
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
                .pulseWidgetStyle()
        }
        .configurationDisplayName("Pulse — une IA")
        .description("La limite la plus proche d'une IA, avec sa projection ; en grand, le graphique et toutes ses limites.")
        .supportedFamilies([.systemSmall, .systemLarge])
        // Les marges viennent de la maquette (14 à 18 pt selon la taille).
        .contentMarginsDisabled()
    }
}

struct AllServicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseAllServices", provider: AllServicesProvider()) { entry in
            AllServicesView(entry: entry)
                .pulseWidgetStyle()
        }
        .configurationDisplayName("Pulse — toutes les IA")
        .description("Les 4 IA d'un coup d'œil : %, projection ou reset.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

extension View {
    /// Thème sombre de Pulse : fond #1C1C1E, textes clairs.
    func pulseWidgetStyle() -> some View {
        foregroundStyle(PulseTheme.text)
            .environment(\.colorScheme, .dark)
            .containerBackground(PulseTheme.background, for: .widget)
    }
}
