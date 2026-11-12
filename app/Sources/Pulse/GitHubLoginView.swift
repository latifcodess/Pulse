import AppKit
import PulseCore
import SwiftUI

/// Connexion au compte GitHub pour Copilot : Pulse affiche un code, que
/// l'utilisateur saisit sur github.com ; Pulse reçoit alors un token.
struct GitHubLoginView: View {
    let monitor: AiMonitor
    let onToken: @MainActor (String) -> Void

    private enum Phase {
        case requesting
        case waiting(DeviceCode)
        case expired
        case denied
        case failed
    }

    @State private var phase: Phase = .requesting
    /// Changé par « Recommencer » : relance la connexion.
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: AiService.copilot.logo(size: 40))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Text("Connexion à GitHub")
                .font(.title3.weight(.semibold))

            switch phase {
            case .requesting:
                ProgressView("Demande d'un code à GitHub…")
                    .controlSize(.small)
            case .waiting(let code):
                Text("Saisissez ce code sur GitHub :")
                    .foregroundStyle(.secondary)
                Text(code.userCode)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Button("Copier le code et ouvrir GitHub") { open(code) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("En attente de votre validation…")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            case .expired:
                retry("Le code a expiré.")
            case .denied:
                retry("La connexion a été refusée sur GitHub.")
            case .failed:
                retry("GitHub ne répond pas. Vérifiez votre connexion à Internet.")
            }
        }
        .padding(24)
        .frame(width: 380)
        .task(id: attempt) { await run() }
    }

    private func retry(_ message: String) -> some View {
        VStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Button("Recommencer") { attempt += 1 }
        }
    }

    private func open(_ code: DeviceCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
        if let url = URL(string: code.verificationUri) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Demande un code, puis interroge GitHub jusqu'à la validation. La tâche
    /// s'arrête toute seule si la fenêtre est fermée.
    private func run() async {
        phase = .requesting
        let monitor = monitor
        guard let code = await Task.detached(priority: .userInitiated, operation: { monitor.copilotDeviceCode() }).value
        else {
            phase = .failed
            return
        }
        phase = .waiting(code)

        var interval = Int(code.interval)
        let deadline = Date.now.addingTimeInterval(TimeInterval(code.expiresIn))
        var failures = 0
        while Date.now < deadline {
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            let deviceCode = code.deviceCode
            let step = await Task.detached(priority: .utility) { monitor.copilotPollDevice(deviceCode: deviceCode) }.value
            switch step {
            case .pending:
                failures = 0
            case .slowDown:
                interval += 5
            case .authorized(let token):
                onToken(token)
                return
            case .expired:
                phase = .expired
                return
            case .denied:
                phase = .denied
                return
            case .failed:
                // Une coupure réseau passagère ne fait pas échouer la connexion.
                failures += 1
                if failures >= 3 {
                    phase = .failed
                    return
                }
            }
        }
        phase = .expired
    }
}
