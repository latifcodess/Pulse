import PulseCore
import SwiftUI

/// La fenêtre d'une IA, ouverte en cliquant sur sa puce (maquette
/// design/pulse-maquettes/Detail.dc.html). 360 pt de large.
struct DetailView: View {
    let app: AppModel
    let model: UsageModel
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onUpdate: () -> Void
    let onQuit: () -> Void

    private var service: AiService { model.service }
    private var thresholds: Thresholds { model.settings.thresholds }

    var body: some View {
        // Redessine toutes les 30 s : « il y a X min », « dans 2 h 05 ».
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            VStack(spacing: 0) {
                header
                    .padding(EdgeInsets(top: 16, leading: 18, bottom: 10, trailing: 16))

                if let nearest = nearestWindow {
                    usageCard(nearest, now: now)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    if let warning = blockedWarning(now: now) {
                        WarningBanner(text: warning)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                    }
                    SectionTitle("Limites")
                        .padding(EdgeInsets(top: 16, leading: 18, bottom: 6, trailing: 18))
                    VStack(spacing: 14) {
                        ForEach(model.windows, id: \.label) { window in
                            LimitRow(window: window, thresholds: thresholds, now: now)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    if let message = StateMessage.message(for: model.state, service: service, refreshInterval: model.refreshInterval) {
                        // Hors ligne : les valeurs affichées sont les dernières connues.
                        MessageCard(text: message.text, icon: message.icon)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                    }
                } else if let message = StateMessage.message(for: model.state, service: service, refreshInterval: model.refreshInterval) {
                    MessageCard(text: message.text, icon: message.icon)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }

                footer(now: now)
                    .padding(.top, 16)
            }
        }
        .frame(width: 360)
        .foregroundStyle(PulseTheme.text)
        .background(PulseTheme.background)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 10) {
            LogoBadge(kind: service.logoKind, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.title)
                    .font(.system(size: 15, weight: .semibold))
                Text("\(StateMessage.status(model.state)) · \(connectionMethod)")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.secondary)
            }
            Spacer(minLength: 8)
            if let plan {
                Text(plan)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PulseTheme.warningText)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(PulseTheme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// « Claude Code », « Compte ChatGPT »…
    private var connectionMethod: String {
        if service == .claude {
            return ClaudeAuthMethod.current.title
        }
        return ConnectionMethod.current(for: service) == .cli ? service.cliName : service.accountName
    }

    /// Le plan de l'abonnement, quand il est connu (Claude via Claude Code).
    private var plan: String? {
        guard service == .claude, ClaudeAuthMethod.current == .claudeCode else { return nil }
        return app.claudeAccount.plan
    }

    // MARK: - Carte principale

    /// La limite la plus proche d'être atteinte.
    private var nearestWindow: UsageWindow? {
        model.windows.max { $0.percent < $1.percent }
    }

    private func usageCard(_ window: UsageWindow, now: Date) -> some View {
        let color = levelColor(window.percent)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(UsageFormat.percent(window.percent))
                    .font(.system(size: 34, weight: .bold))
                    .kerning(-1)
                    .foregroundStyle(color)
                    .animatedNumber(window.percent)
                Text(Self.limitPhrase(window.label))
                    .font(.system(size: 13))
                    .foregroundStyle(PulseTheme.secondary)
            }
            ProjectionChart(
                samples: app.history.samples(service, label: window.label),
                now: now,
                percent: window.percent,
                resetsAt: window.resetsAt.map(Self.date),
                projectedFullAt: window.projectedFullAt.map(Self.date),
                color: color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PulseTheme.cardBorder))
    }

    /// « de la session 5 h », « de la semaine », ou le nom de la limite.
    static func limitPhrase(_ label: String) -> String {
        let lower = label.lowercased(with: Locale(identifier: "fr_FR"))
        guard lower.hasPrefix("session") || lower.hasPrefix("semaine") else { return label }
        return "de la " + lower.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
    }

    /// « Au rythme actuel, tu seras bloqué de 15:32 à 17:00. » pour la
    /// première limite qui sera atteinte avant son reset.
    private func blockedWarning(now: Date) -> String? {
        let first = model.windows
            .compactMap { window in window.projectedFullAt.map { (window, Self.date($0)) } }
            .min { $0.1 < $1.1 }
        guard let (window, fullAt) = first else { return nil }
        let full = Self.time(fullAt, now: now)
        guard let resetsAt = window.resetsAt.map(Self.date) else {
            return "Au rythme actuel, la limite sera atteinte vers \(full)."
        }
        return "Au rythme actuel, tu seras bloqué de \(full) à \(Self.time(resetsAt, now: now))."
    }

    // MARK: - Pied

    private func footer(now: Date) -> some View {
        HStack(spacing: 6) {
            Text(Self.updatedText(model.lastUpdated, now: now))
                .font(.system(size: 12))
                .foregroundStyle(PulseTheme.secondary)
            Spacer(minLength: 8)
            if let version = app.updater.availableUpdate?.version {
                Button(action: onUpdate) {
                    Label("Pulse \(version)", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulseTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Une mise à jour de Pulse est disponible")
            }
            IconButton(systemImage: "arrow.clockwise", help: "Actualiser", isBusy: model.isRefreshing, action: onRefresh)
            IconButton(systemImage: "gearshape", help: "Réglages", action: onSettings)
            IconButton(systemImage: "power", help: "Quitter Pulse", action: onQuit)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .overlay(alignment: .top) {
            Rectangle().fill(PulseTheme.cardBorder).frame(height: 1)
        }
    }

    /// « Mis à jour il y a 1 min ».
    static func updatedText(_ date: Date?, now: Date) -> String {
        let text = UsageFormat.updated(date, now: now)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Outils

    private func levelColor(_ percent: Double) -> Color {
        PulseTheme.levelColor(percent, warning: thresholds.warning, critical: thresholds.critical)
    }

    static func date(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// « 17:00 », ou « lun. 09:00 » si ce n'est pas aujourd'hui.
    static func time(_ date: Date, now: Date) -> String {
        let time = UsageFormat.hourMinute(date)
        guard !Calendar.current.isDate(date, inSameDayAs: now) else { return time }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_FR"))) + " " + time
    }
}

// MARK: - Éléments

/// Une limite : nom, %, barre, reset et projection.
private struct LimitRow: View {
    let window: UsageWindow
    let thresholds: Thresholds
    let now: Date

    var body: some View {
        let color = PulseTheme.levelColor(window.percent, warning: thresholds.warning, critical: thresholds.critical)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(window.label)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(UsageFormat.percent(window.percent))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .animatedNumber(window.percent)
            }
            LimitBar(percent: window.percent, color: color)
            HStack {
                Text(resetText)
                    .foregroundStyle(PulseTheme.secondary)
                Spacer(minLength: 8)
                if let fullAt = window.projectedFullAt.map(DetailView.date) {
                    Text("Limite vers \(DetailView.time(fullAt, now: now))")
                        .foregroundStyle(PulseTheme.warningText)
                } else {
                    Text("Tiendra jusqu'au reset")
                        .foregroundStyle(PulseTheme.secondary)
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
        }
    }

    /// « Reset à 17:00 · dans 2 h 05 », ou « Reset lun. 09:00 » un autre jour.
    private var resetText: String {
        guard let resetsAt = window.resetsAt.map(DetailView.date) else { return "Reset inconnu" }
        if Calendar.current.isDate(resetsAt, inSameDayAs: now) {
            return "Reset à \(UsageFormat.hourMinute(resetsAt)) · \(UsageFormat.remaining(resetsAt.timeIntervalSince(now)))"
        }
        return "Reset \(DetailView.time(resetsAt, now: now))"
    }
}

/// « LIMITES » : petit titre de section en capitales.
private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(PulseTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bandeau orange : la limite sera atteinte avant le reset.
private struct WarningBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseTheme.warningText)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(PulseTheme.warningSoftText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(PulseTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Carte de message : non connecté, hors ligne, expiré…
private struct MessageCard: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(PulseTheme.secondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(PulseTheme.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PulseTheme.cardBorder))
    }
}

/// Bouton carré de 32 pt avec une icône, et son infobulle.
struct IconButton: View {
    let systemImage: String
    let help: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 32, height: 32)
            .background(PulseTheme.controlFill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension AiService {
    /// Le logo de l'IA, pour les composants partagés.
    var logoKind: ServiceLogo.Kind {
        switch self {
        case .claude: .claude
        case .chatGpt: .chatGpt
        case .gemini: .gemini
        case .copilot: .copilot
        }
    }
}
