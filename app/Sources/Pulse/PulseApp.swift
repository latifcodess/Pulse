import SwiftUI

@main
struct PulseApp: App {
    @State private var usage = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text(usage.sessionText)
            }
        }
    }
}
