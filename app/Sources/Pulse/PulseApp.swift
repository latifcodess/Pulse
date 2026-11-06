import SwiftUI

@main
struct PulseApp: App {
    var body: some Scene {
        MenuBarExtra("Pulse", systemImage: "waveform.path.ecg") {
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
