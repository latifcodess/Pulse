import Observation
import OSLog
import ServiceManagement

/// Ouvrir Pulse au démarrage de la session. C'est macOS qui garde ce réglage
/// (Réglages Système › Général › Ouverture) : on le lit chez lui, rien n'est
/// rangé dans UserDefaults.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    private static let logger = Logger(subsystem: "ch.latifcodess.pulse", category: "launch-at-login")

    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set { setEnabled(newValue) }
    }

    /// macOS attend une validation de l'utilisateur dans les Réglages Système.
    var needsApproval: Bool { status == .requiresApproval }

    /// À appeler quand la fenêtre réapparaît : le réglage a pu changer dans
    /// les Réglages Système.
    func reload() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            Self.logger.error("Ouverture au démarrage : \(error.localizedDescription, privacy: .public)")
            errorMessage = "macOS a refusé la modification. Placez Pulse dans le dossier Applications, puis réessayez."
        }
        reload()
    }
}
