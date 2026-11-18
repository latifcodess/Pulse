import AppKit
import Charts
import SwiftUI

// Composants réutilisables de Pulse (app, et plus tard widget).

// MARK: - Pastille de logo

/// Le logo officiel d'une IA, dans sa couleur, sans fond.
struct LogoBadge: View {
    let kind: ServiceLogo.Kind
    /// Côté du logo, en points.
    var size: CGFloat = 20
    /// Sur fond clair (barre des menus claire), un logo plus foncé reste lisible.
    var onLightBackground = false

    var body: some View {
        Image(nsImage: ServiceLogo.image(kind, size: size))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .foregroundStyle(onLightBackground ? kind.inkOnLight : kind.ink)
    }
}

// MARK: - Anneau

/// Un anneau de progression (style « Anneaux » de la barre des menus).
struct UsageRing: View {
    let percent: Double
    let color: Color
    var size: CGFloat = 16
    /// Le fond de l'anneau : blanc à 18 % (noir sur une barre claire).
    var trackColor: Color = .white.opacity(0.18)
    /// Rayon et épaisseur par rapport au côté. Barre des menus : rayon 14 et
    /// trait 6 dans un carré de 36 ; widget : rayon 40 et trait 12 sur 100.
    var radiusRatio: CGFloat = 14 / 36
    var lineWidthRatio: CGFloat = 6 / 36
    var lineCap: CGLineCap = .butt

    /// L'anneau du petit widget.
    static func widget(percent: Double, color: Color, size: CGFloat = 64) -> UsageRing {
        UsageRing(
            percent: percent, color: color, size: size, trackColor: .white.opacity(0.10),
            radiusRatio: 0.40, lineWidthRatio: 0.12, lineCap: .round)
    }

    var body: some View {
        let lineWidth = size * lineWidthRatio
        let diameter = size * radiusRatio * 2
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(percent, 0), 100) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.4), value: percent)
        }
        .frame(width: diameter, height: diameter)
        .frame(width: size, height: size)
    }
}

// MARK: - Icône de Pulse

/// Le tracé de pouls de Pulse (style « Compact » de la barre des menus) :
/// « M2 12h4l3-8 4 16 3-8h6 » dans un carré de 24.
struct PulseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [(2, 12), (6, 12), (9, 4), (13, 20), (16, 12), (22, 12)]
            .map { CGPoint(x: rect.minX + $0.0 / 24 * rect.width, y: rect.minY + $0.1 / 24 * rect.height) }
        var path = Path()
        path.addLines(points)
        return path
    }
}

// MARK: - Barre de limite

/// La barre d'une limite : 6 pt de haut, coins arrondis, fond blanc à 10 %.
struct LimitBar: View {
    let percent: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.white.opacity(0.10))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(percent, 0), 100) / 100)
                    .animation(.smooth(duration: 0.4), value: percent)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Graphique de projection

/// Une mesure de la limite : heure et % utilisé.
struct ChartSample: Identifiable, Equatable, Sendable {
    let date: Date
    let percent: Double
    var id: Date { date }
}

/// L'utilisation de la fenêtre en cours : zone remplie jusqu'à maintenant,
/// projection en pointillés jusqu'à 100 %, ligne verticale au reset, ligne
/// 100 % en pointillés rouges, heures en abscisse.
struct ProjectionChart: View {
    let samples: [ChartSample]
    let now: Date
    let percent: Double
    let resetsAt: Date?
    let projectedFullAt: Date?
    let color: Color
    var height: CGFloat = 128
    /// Version du grand widget : heure seule au point 100 %, pas de point
    /// « maintenant », étiquettes plus petites.
    var compact = false

    var body: some View {
        let domain = xDomain
        Chart {
            // Ligne 100 %, en pointillés rouges.
            RuleMark(y: .value("Limite", 100))
                .foregroundStyle(PulseTheme.critical.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            RuleMark(y: .value("Zéro", 0))
                .foregroundStyle(Color.white.opacity(0.10))
                .lineStyle(StrokeStyle(lineWidth: 1))

            // Utilisation mesurée, jusqu'à maintenant (dès qu'il y a deux mesures).
            ForEach(points.count > 1 ? points : []) { sample in
                AreaMark(x: .value("Heure", sample.date), y: .value("%", sample.percent))
                    .foregroundStyle(color.opacity(0.16))
                    .interpolationMethod(.linear)
                LineMark(x: .value("Heure", sample.date), y: .value("%", sample.percent), series: .value("Série", "mesure"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }

            // Projection jusqu'à 100 %.
            if let projectedFullAt {
                LineMark(x: .value("Heure", now), y: .value("%", percent), series: .value("Série", "projection"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                LineMark(x: .value("Heure", projectedFullAt), y: .value("%", 100), series: .value("Série", "projection"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                let fullOnLeft = fraction(projectedFullAt, in: domain) < 0.5
                PointMark(x: .value("Heure", projectedFullAt), y: .value("%", 100))
                    .symbol { Circle().fill(PulseTheme.critical).frame(width: 7, height: 7) }
                    .annotation(
                        position: fullOnLeft ? .bottomTrailing : .bottomLeading,
                        alignment: fullOnLeft ? .leading : .trailing,
                        spacing: 4
                    ) {
                        Text(compact
                            ? ChartFormat.time(projectedFullAt, now: now)
                            : "100 % vers \(ChartFormat.time(projectedFullAt, now: now))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PulseTheme.criticalText)
                            .padding(.horizontal, 3)
                            .background(PulseTheme.background)
                    }
            }

            // Reset.
            if let resetsAt, resetsAt <= domain.upperBound {
                RuleMark(x: .value("Reset", resetsAt))
                    .foregroundStyle(PulseTheme.accent.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }

            // Maintenant. Au bord gauche du graphique, le texte passe à droite
            // du point ; près de 0 %, au-dessus (sous le point, il toucherait l'axe).
            let nowOnLeft = fraction(now, in: domain) < 0.25
            let nowIsLow = percent < 35
            // Dans le widget, le point n'apparaît que s'il est seul (pas encore de courbe).
            if !compact || points.count < 2 {
                PointMark(x: .value("Heure", now), y: .value("%", percent))
                    .symbol {
                        Circle()
                            .fill(PulseTheme.background)
                            .overlay(Circle().stroke(color, lineWidth: 2.4))
                            .frame(width: 8, height: 8)
                    }
                    .annotation(
                        position: nowIsLow
                            ? (nowOnLeft ? .topTrailing : .topLeading)
                            : (nowOnLeft ? .bottomTrailing : .bottomLeading),
                        alignment: nowOnLeft ? .leading : .trailing,
                        spacing: 4
                    ) {
                        Text("maintenant")
                            .font(.system(size: 11))
                            .foregroundStyle(PulseTheme.text)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis {
            let marks = axisMarks(in: domain)
            let multiDay = Self.isMultiDay(domain)
            AxisMarks(values: marks) { value in
                let date = value.as(Date.self)
                let isLast = date == marks.last && marks.last.map { domain.upperBound.timeIntervalSince($0) < 1800 } == true
                // La dernière étiquette (souvent le reset) est alignée sur le bord droit.
                AxisValueLabel(anchor: isLast ? .topTrailing : .top, collisionResolution: .disabled) {
                    if let date {
                        let isReset = resetsAt.map { abs($0.timeIntervalSince(date)) < 60 } ?? false
                        // Sur plusieurs jours : le jour (« jeu. »), et le jour et l'heure du reset.
                        let resetText = multiDay ? ChartFormat.dayAndTime(date) : ChartFormat.time(date)
                        let text = isReset
                            ? (compact ? resetText : resetText + " reset")
                            : (multiDay ? ChartFormat.day(date) : ChartFormat.time(date))
                        Text(text)
                            .font(.system(size: compact ? 10 : 11))
                            .monospacedDigit()
                            .foregroundStyle(isReset ? PulseTheme.accent : PulseTheme.tertiary)
                    }
                }
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.4), value: percent)
    }

    /// Les mesures, terminées par la valeur actuelle.
    private var points: [ChartSample] {
        var points = samples.filter { $0.date < now }
        points.append(ChartSample(date: now, percent: percent))
        return points
    }

    /// Du début de la fenêtre (première mesure, au plus tard 30 min avant
    /// maintenant) jusqu'au reset (limite de la semaine comprise), ou un peu
    /// après la projection.
    private var xDomain: ClosedRange<Date> {
        let start = min(samples.first?.date ?? now, now.addingTimeInterval(-30 * 60))
        var end = now.addingTimeInterval(60 * 60)
        if let projectedFullAt { end = max(end, projectedFullAt.addingTimeInterval(15 * 60)) }
        if let resetsAt, resetsAt > now, resetsAt.timeIntervalSince(now) < 8 * 24 * 3600 {
            end = resetsAt
        }
        return start...max(end, now.addingTimeInterval(60))
    }

    /// Plus d'un jour et demi : l'axe montre des jours plutôt que des heures.
    private static func isMultiDay(_ domain: ClosedRange<Date>) -> Bool {
        domain.upperBound.timeIntervalSince(domain.lowerBound) > 36 * 3600
    }

    /// La position d'une date dans le graphique, de 0 (gauche) à 1 (droite).
    private func fraction(_ date: Date, in domain: ClosedRange<Date>) -> Double {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return span > 0 ? date.timeIntervalSince(domain.lowerBound) / span : 0
    }

    /// Des heures pleines (ou des débuts de jour), et l'heure du reset si
    /// elle est dans le graphique. Environ 5 étiquettes.
    private func axisMarks(in domain: ClosedRange<Date>) -> [Date] {
        let calendar = Calendar.current
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let multiDay = Self.isMultiDay(domain)
        let unit: TimeInterval = multiDay ? 24 * 3600 : 3600
        let step = max(1, Int((span / unit / 5).rounded(.up)))
        var marks: [Date] = []
        var date = calendar.dateInterval(of: multiDay ? .day : .hour, for: domain.lowerBound)?.end ?? domain.lowerBound
        var index = 0
        while date < domain.upperBound.addingTimeInterval(-unit / 3) {
            let keep = multiDay ? index % step == 0 : calendar.component(.hour, from: date) % step == 0
            if keep { marks.append(date) }
            index += 1
            date = multiDay
                ? calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(unit)
                : date.addingTimeInterval(unit)
        }
        if let resetsAt, domain.contains(resetsAt) {
            // Pas d'étiquette trop proche du reset : elles se chevaucheraient.
            // Sur plusieurs jours, « mar. 17:00 reset » occupe environ le tiers de la largeur.
            let gap = multiDay ? max(Double(step) * unit, span * 0.3) : Double(step) * unit
            marks.removeAll { abs($0.timeIntervalSince(resetsAt)) < gap }
            marks.append(resetsAt)
        }
        return marks
    }
}

enum ChartFormat {
    private static let locale = Locale(identifier: "fr_FR")

    /// « 17:00 ».
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    /// « 17:00 » aujourd'hui, sinon « mar. 17:00 ».
    static func time(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? time(date) : dayAndTime(date)
    }

    /// « jeu. ».
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }

    /// « mar. 17:00 ».
    static func dayAndTime(_ date: Date) -> String {
        "\(day(date)) \(time(date))"
    }
}
