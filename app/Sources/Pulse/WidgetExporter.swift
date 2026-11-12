import Foundation
import OSLog
import PulseCore
import WidgetKit

/// Écrit le fichier partagé avec le widget après chaque actualisation, puis
/// demande à macOS de redessiner les widgets.
@MainActor
final class WidgetExporter {
    private var pending: Task<Void, Never>?
    private static let logger = Logger(subsystem: "ch.latifcodess.pulse", category: "widget")

    /// Les IA s'actualisent souvent presque en même temps : on attend une
    /// seconde pour n'écrire qu'une fois.
    func scheduleExport(of models: [UsageModel]) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            export(models)
        }
    }

    private func export(_ models: [UsageModel]) {
        let snapshot = WidgetSnapshot(writtenAt: .now, services: models.map(Self.service(from:)))
        do {
            try snapshot.write()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Self.logger.error("Fichier du widget non écrit : \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func service(from model: UsageModel) -> WidgetSnapshot.Service {
        let thresholds = model.settings.thresholds
        return WidgetSnapshot.Service(
            id: model.service.storageKey,
            title: model.service.title,
            followed: model.isEnabled,
            state: state(model.state),
            updatedAt: model.lastUpdated,
            warning: thresholds.warning,
            critical: thresholds.critical,
            windows: model.windows.map { window in
                WidgetSnapshot.Window(
                    label: window.label,
                    percent: window.percent,
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    projectedFullAt: window.projectedFullAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            }
        )
    }

    private static func state(_ state: AiState?) -> WidgetSnapshot.State {
        switch state {
        case nil: .loading
        case .ok: .ok
        case .offline: .offline
        case .notConnected: .notConnected
        case .expired: .expired
        case .blocked: .blocked
        case .unavailable: .unavailable
        }
    }
}
