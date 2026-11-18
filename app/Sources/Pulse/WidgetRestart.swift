import Darwin
import Foundation
import OSLog
import WidgetKit

/// Après une mise à jour, le processus du widget peut continuer à tourner avec
/// l'ancien code : remplacer le fichier ne change pas ce qu'un processus déjà
/// lancé exécute, et macOS ne le relance pas toujours. Au premier lancement
/// d'un nouveau build, Pulse arrête donc l'ancien processus de son propre
/// widget ; macOS le relance avec le nouveau code au prochain affichage.
enum WidgetRestart {
    private static let lastBuildKey = "widget.lastLaunchedBuilds"
    private static let logger = Logger(subsystem: "ch.latifcodess.pulse", category: "widget")

    static func afterUpdateIfNeeded() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        // Un build par emplacement de l'app : une copie de développement (même
        // build, autre dossier) n'empêche pas celle d'Applications de le faire.
        let path = Bundle.main.bundlePath
        let defaults = UserDefaults.standard
        var lastBuilds = defaults.dictionary(forKey: lastBuildKey) as? [String: String] ?? [:]
        guard lastBuilds[path] != build else { return }
        lastBuilds[path] = build
        defaults.set(lastBuilds, forKey: lastBuildKey)

        // Uniquement l'exécutable du widget embarqué dans cette copie de Pulse.
        guard let widget = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("PulseWidget.appex/Contents/MacOS/PulseWidget")
            .resolvingSymlinksInPath().path
        else { return }
        let stale = processes(runningExecutable: widget)
        for pid in stale {
            kill(pid, SIGTERM)
        }
        logger.notice("Build \(build, privacy: .public) : \(stale.count, privacy: .public) ancien(s) processus du widget arrêté(s)")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Les processus de l'utilisateur dont l'exécutable est exactement `path`.
    private static func processes(runningExecutable path: String) -> [pid_t] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 16)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let me = getpid()
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return pids.prefix(Int(filled) / MemoryLayout<pid_t>.size).filter { pid in
            guard pid > 0, pid != me else { return false }
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { return false }
            let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self) == path
        }
    }
}
