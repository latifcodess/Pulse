import Foundation
import SwiftUI

/// Niveau d'alerte d'une limite : orange au-dessus de 75 %, rouge au-dessus de 90 %.
enum UsageLevel {
    case normal
    case warning
    case critical

    init(percent: Double) {
        if percent > 90 {
            self = .critical
        } else if percent > 75 {
            self = .warning
        } else {
            self = .normal
        }
    }

    /// nil : couleur par défaut du système.
    var color: Color? {
        switch self {
        case .normal: nil
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// Textes affichés, en français.
enum UsageFormat {
    private static let locale = Locale(identifier: "fr_FR")

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    /// « Réinitialisé à 17:00 · dans 2 h 15 », avec le jour s'il ne s'agit pas d'aujourd'hui.
    static func reset(_ resetsAt: Int64?, now: Date) -> String {
        guard let resetsAt else { return "Heure de réinitialisation inconnue" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))

        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        let day =
            Calendar.current.isDate(date, inSameDayAs: now)
            ? "" : date.formatted(.dateTime.weekday(.abbreviated).locale(locale)) + " "
        return "Réinitialisé \(day)à \(time) · \(remaining(date.timeIntervalSince(now)))"
    }

    /// « dans 45 min », « dans 2 h 15 », « dans 3 j 4 h ».
    static func remaining(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "dans moins d'1 min" }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "dans \(minutes) min"
        }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "dans \(hours) h" : "dans \(hours) h \(String(format: "%02d", rest))"
        }
        let days = hours / 24
        let rest = hours % 24
        return rest == 0 ? "dans \(days) j" : "dans \(days) j \(rest) h"
    }

    static func updated(_ date: Date?, now: Date) -> String {
        guard let date else { return "pas encore mis à jour" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 {
            return "mis à jour à l'instant"
        }
        if minutes < 60 {
            return "mis à jour il y a \(minutes) min"
        }
        return "mis à jour il y a \(minutes / 60) h"
    }
}
