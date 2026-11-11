import AppKit
import Darwin
import Foundation
import Observation
import OSLog
import PulseCore

/// Les mises à jour de Pulse.
///
/// Le cœur Rust cherche la dernière release GitHub, télécharge le DMG et
/// vérifie son empreinte. Ici, on monte le DMG, on contrôle l'app qu'il
/// contient, on l'échange avec l'app actuelle, puis on relance Pulse.
@MainActor
@Observable
final class Updater {
    enum Phase {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case downloading(UpdateInfo)
        case installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Heure de la dernière recherche réussie.
    private(set) var lastCheck: Date?

    /// Recherche automatique, une fois par jour.
    var automaticChecks: Bool {
        didSet { UserDefaults.standard.set(automaticChecks, forKey: Self.automaticKey) }
    }

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    /// Envoie une notification (titre, texte). Branché par AppModel.
    @ObservationIgnored var notify: ((_ title: String, _ body: String) -> Void)?

    private static let automaticKey = "updates.automatic"
    private static let notifiedVersionKey = "updates.notifiedVersion"
    /// Argument de lancement ajouté par le script de relance, après une mise à jour.
    private static let updatedFlag = "--updated"
    /// Début du nom des copies de travail, posées à côté de l'app.
    private nonisolated static let stagingPrefix = ".Pulse-update-"
    private nonisolated static let logger = Logger(subsystem: "ch.latifcodess.pulse", category: "updates")

    init() {
        automaticChecks = UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    /// À appeler une fois au lancement, quand `notify` est branché.
    func start() {
        if CommandLine.arguments.contains(Self.updatedFlag) {
            Self.logger.notice("Mise à jour installée : version \(self.currentVersion, privacy: .public)")
            notify?("Pulse a été mis à jour", "La version \(currentVersion) est installée.")
        }
        Task.detached(priority: .background) { Self.removeLeftovers() }
        Task { await automaticLoop() }
    }

    var availableUpdate: UpdateInfo? {
        if case .available(let info) = phase { info } else { nil }
    }

    // MARK: - Recherche

    /// `userInitiated` : lancée par un bouton. Le résultat est alors toujours
    /// affiché, que ce soit « à jour » ou une erreur.
    func check(userInitiated: Bool) async {
        switch phase {
        case .checking, .downloading, .installing: return
        default: break
        }
        let previous = phase
        phase = .checking
        let version = currentVersion
        let result = await Task.detached(priority: .utility) { checkForUpdate(currentVersion: version) }.value

        switch result {
        case .upToDate:
            lastCheck = .now
            phase = .upToDate
        case .available(let info):
            lastCheck = .now
            phase = .available(info)
            if !userInitiated {
                notifyOnce(about: info)
            }
        case .failed(let reason):
            Self.logger.notice("Recherche de mise à jour : \(String(describing: reason), privacy: .public)")
            // Une recherche automatique qui échoue reste discrète : l'affichage
            // ne change pas (une mise à jour déjà trouvée reste proposée).
            phase = userInitiated ? .failed(Self.message(for: reason)) : previous
        }
    }

    private func automaticLoop() async {
        // Laisse l'app démarrer avant la première recherche.
        try? await Task.sleep(for: .seconds(15))
        while !Task.isCancelled {
            if automaticChecks {
                await check(userInitiated: false)
            }
            try? await Task.sleep(for: .seconds(24 * 3600))
        }
    }

    /// Une seule notification par version trouvée.
    private func notifyOnce(about info: UpdateInfo) {
        guard UserDefaults.standard.string(forKey: Self.notifiedVersionKey) != info.version else { return }
        UserDefaults.standard.set(info.version, forKey: Self.notifiedVersionKey)
        notify?("Pulse \(info.version) est disponible", "Cliquez pour l'installer depuis les réglages.")
    }

    // MARK: - Installation

    func install(_ info: UpdateInfo) async {
        // Un deuxième clic pendant le téléchargement ne relance rien.
        guard case .available = phase else { return }
        phase = .downloading(info)
        let directory = Self.downloadDirectory.path
        let outcome = await Task.detached(priority: .userInitiated) {
            downloadUpdate(info: info, directory: directory)
        }.value

        switch outcome {
        case .failed(let reason):
            phase = .failed(Self.message(for: reason))
        case .downloaded(let path):
            await installDownloaded(dmg: URL(fileURLWithPath: path), version: info.version)
        }
    }

    /// Installe un DMG déjà téléchargé et vérifié, puis relance Pulse.
    private func installDownloaded(dmg: URL, version: String) async {
        phase = .installing
        let target = Bundle.main.bundleURL
        let result = await Task.detached(priority: .userInitiated) {
            Self.replaceApp(at: target, withAppIn: dmg, version: version)
        }.value

        switch result {
        case .success(let oldApp):
            try? FileManager.default.removeItem(at: dmg)
            relaunch(app: target, removing: oldApp)
        case .failure(let error):
            Self.logger.error("Installation : \(error.message, privacy: .public)")
            if error.manualInstall {
                // L'utilisateur glisse lui-même la nouvelle version dans Applications.
                NSWorkspace.shared.open(dmg)
            } else {
                try? FileManager.default.removeItem(at: dmg)
            }
            phase = .failed(error.message)
        }
    }

    private struct InstallError: Error {
        let message: String
        /// Vrai : l'image disque est saine, on l'ouvre pour une installation à la main.
        let manualInstall: Bool

        static func manual(_ message: String) -> InstallError {
            InstallError(message: message, manualInstall: true)
        }

        static func invalid(_ message: String) -> InstallError {
            InstallError(message: message, manualInstall: false)
        }
    }

    private static var downloadDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ch.latifcodess.pulse/Updates", isDirectory: true)
    }

    /// Monte le DMG, contrôle l'app qu'il contient, la copie à côté de l'app
    /// actuelle, puis échange les deux. Renvoie l'emplacement où se trouve
    /// désormais l'ancienne version, à supprimer une fois Pulse fermé.
    private nonisolated static func replaceApp(
        at target: URL, withAppIn dmg: URL, version: String
    ) -> Result<URL, InstallError> {
        let files = FileManager.default
        let parent = target.deletingLastPathComponent()
        guard files.isWritableFile(atPath: parent.path) else {
            return .failure(.manual(
                "Pulse ne peut pas se remplacer dans ce dossier. Glissez la nouvelle version dans Applications."))
        }

        let mountPoint = files.temporaryDirectory
            .appendingPathComponent("Pulse-update-\(UUID().uuidString)", isDirectory: true)
        guard (try? files.createDirectory(at: mountPoint, withIntermediateDirectories: true)) != nil,
            run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                      "-mountpoint", mountPoint.path]) == 0
        else {
            _ = rmdir(mountPoint.path)
            return .failure(.invalid("Impossible d'ouvrir l'image disque téléchargée."))
        }
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            // rmdir ne supprime qu'un dossier vide : sans risque si le volume
            // est encore monté.
            _ = rmdir(mountPoint.path)
        }

        let newApp = mountPoint.appendingPathComponent("Pulse.app")
        if let problem = validationProblem(of: newApp, version: version) {
            return .failure(.invalid(problem))
        }

        let staged = parent.appendingPathComponent("\(stagingPrefix)\(UUID().uuidString).app")
        guard run("/usr/bin/ditto", [newApp.path, staged.path]) == 0 else {
            try? files.removeItem(at: staged)
            return .failure(.manual(
                "Impossible de copier la nouvelle version à côté de l'ancienne. Glissez-la dans Applications."))
        }
        // Échange atomique des deux dossiers : à tout instant, une app complète
        // se trouve à l'emplacement de Pulse.
        guard renamex_np(staged.path, target.path, UInt32(RENAME_SWAP)) == 0 else {
            let code = errno
            logger.error("Échange des deux versions refusé : errno \(code)")
            try? files.removeItem(at: staged)
            return .failure(.manual(
                "macOS a refusé de remplacer Pulse. Glissez la nouvelle version dans Applications."))
        }
        // `staged` contient maintenant l'ancienne version.
        return .success(staged)
    }

    /// L'app de la mise à jour doit être Pulse, dans la version annoncée,
    /// intacte, et capable de tourner sur ce Mac. Renvoie le problème trouvé.
    private nonisolated static func validationProblem(of app: URL, version: String) -> String? {
        guard let bundle = Bundle(url: app),
            let ownIdentifier = Bundle.main.bundleIdentifier,
            bundle.bundleIdentifier == ownIdentifier,
            bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version
        else {
            return "La mise à jour ne contient pas Pulse \(version)."
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            return "L'app contenue dans la mise à jour est endommagée."
        }
        guard bundle.executableArchitectures?.contains(where: { $0.intValue == ownArchitecture }) == true else {
            return "Cette mise à jour n'est pas compatible avec le processeur de ce Mac."
        }
        if let minimum = bundle.infoDictionary?["LSMinimumSystemVersion"] as? String,
            let required = systemVersion(minimum),
            !ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
        {
            return "Cette mise à jour demande macOS \(minimum) ou plus récent."
        }
        return nil
    }

    #if arch(arm64)
        private nonisolated static let ownArchitecture = NSBundleExecutableArchitectureARM64
    #else
        private nonisolated static let ownArchitecture = NSBundleExecutableArchitectureX86_64
    #endif

    /// « 15.0 » → version 15.0.0. nil si le texte n'est pas un numéro de version.
    private nonisolated static func systemVersion(_ text: String) -> OperatingSystemVersion? {
        let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(numbers.count), !numbers.contains(nil) else { return nil }
        let parts = numbers.compactMap { $0 } + [0, 0]
        return OperatingSystemVersion(majorVersion: parts[0], minorVersion: parts[1], patchVersion: parts[2])
    }

    /// Lance un petit script qui attend la fermeture de Pulse, supprime
    /// l'ancienne version, puis ouvre la nouvelle. Ensuite, quitte Pulse.
    private func relaunch(app: URL, removing oldApp: URL) {
        let script = """
            pid="$1"; app="$2"; old="$3"
            tries=0
            while kill -0 "$pid" 2>/dev/null; do
                tries=$((tries + 1))
                if [ "$tries" -gt 150 ]; then kill -9 "$pid" 2>/dev/null; fi
                /bin/sleep 0.2
            done
            /bin/rm -rf "$old"
            /usr/bin/open -n "$app" --args \(Self.updatedFlag)
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Les chemins sont passés en arguments, jamais insérés dans le script.
        process.arguments = ["-c", script, "sh", "\(ProcessInfo.processInfo.processIdentifier)",
                             app.path, oldApp.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            // La nouvelle version est déjà en place : elle servira au prochain lancement.
            Self.logger.error("Relance impossible : \(error.localizedDescription, privacy: .public)")
            phase = .failed("La mise à jour est installée. Quittez puis rouvrez Pulse pour l'utiliser.")
        }
    }

    /// Supprime les copies de travail qu'une mise à jour interrompue aurait
    /// laissées à côté de l'app.
    private nonisolated static func removeLeftovers() {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names where name.hasPrefix(stagingPrefix) && name.hasSuffix(".app") {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }

    /// Lance une commande et attend son code de sortie.
    private nonisolated static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func message(for reason: UpdateFailure) -> String {
        switch reason {
        case .offline: "Pas de connexion à Internet."
        case .noRelease: "Aucune version publiée pour l'instant."
        case .rateLimited: "GitHub limite les requêtes. Réessayez dans une heure."
        case .invalidRelease: "La version publiée est incomplète (DMG ou empreinte manquante)."
        case .checksumMismatch: "Le fichier téléchargé est corrompu : il a été supprimé."
        case .writeFailed: "Impossible d'enregistrer le fichier téléchargé."
        case .unavailable: "GitHub ne répond pas correctement. Réessayez plus tard."
        }
    }
}
