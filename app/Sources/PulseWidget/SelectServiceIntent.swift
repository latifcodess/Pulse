import AppIntents
import WidgetKit

/// L'IA affichée par le petit widget, choisie dans sa configuration.
enum WidgetService: String, AppEnum {
    case claude, chatgpt, gemini, copilot

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "IA"
    static let caseDisplayRepresentations: [WidgetService: DisplayRepresentation] = [
        .claude: "Claude",
        .chatgpt: "ChatGPT",
        .gemini: "Gemini",
        .copilot: "Copilot",
    ]
}

struct SelectServiceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir l'IA"
    static let description = IntentDescription("L'IA affichée dans le widget.")

    @Parameter(title: "IA", default: .claude)
    var service: WidgetService

    init() {}

    init(service: WidgetService) {
        self.service = service
    }
}
