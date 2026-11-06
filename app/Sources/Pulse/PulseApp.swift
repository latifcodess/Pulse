import PulseCore
import SwiftUI

@main
struct PulseApp: App {
    private let sessionText = PulseApp.claudeSessionText()

    var body: some Scene {
        MenuBarExtra {
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text(sessionText)
            }
        }
    }

    private static func claudeSessionText() -> String {
        guard case .ok(let usage) = AiMonitor().claudeFixtureState(),
            let session = usage.windows.first(where: { $0.label == "Session (5 h)" })
        else {
            return "indisponible"
        }
        return "\(Int(session.percent.rounded())) %"
    }
}
