import Foundation
import Observation
import PulseCore

/// Les points du graphique de la fenêtre d'une IA : (heure, %) de chaque
/// limite, notés à chaque actualisation réussie. Uniquement pour l'affichage,
/// en mémoire : la projection elle-même est calculée par le cœur Rust.
@MainActor
@Observable
final class UsageHistoryRecorder {
    private struct Series {
        var resetsAt: Int64?
        var samples: [ChartSample]
    }

    private var series: [String: Series] = [:]
    /// Au-delà, les points ne sont plus utiles au graphique.
    private static let maxAge: TimeInterval = 12 * 3600

    func record(_ service: AiService, windows: [UsageWindow], at now: Date = .now) {
        for window in windows {
            let key = Self.key(service, window.label)
            var current = series[key] ?? Series(resetsAt: window.resetsAt, samples: [])
            // Nouvelle fenêtre : l'heure de reset a changé, ou le % est retombé.
            let resetMoved = zip(current.resetsAt, window.resetsAt).map { abs($0 - $1) > 120 } ?? false
            let dropped = (current.samples.last?.percent).map { window.percent < $0 - 5 } ?? false
            if resetMoved || dropped {
                current.samples.removeAll()
            }
            current.resetsAt = window.resetsAt
            current.samples.removeAll { now.timeIntervalSince($0.date) > Self.maxAge }
            current.samples.append(ChartSample(date: now, percent: window.percent))
            series[key] = current
        }
    }

    func samples(_ service: AiService, label: String) -> [ChartSample] {
        series[Self.key(service, label)]?.samples ?? []
    }

    private static func key(_ service: AiService, _ label: String) -> String {
        "\(service.storageKey)|\(label)"
    }
}

/// Les deux valeurs si elles existent toutes les deux.
private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
