import AppKit
import Foundation
import Observation
import OSLog
import PulseCore
import UserNotifications

/// Les notifications macOS. Le moteur Rust décide quand prévenir ; ici, on
/// rédige le texte en français et on l'envoie à macOS.
@MainActor
@Observable
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    /// Les règles, rangées en JSON dans les préférences (ce ne sont pas des secrets).
    var rules: [AlertRule] {
        didSet { UserDefaults.standard.set(alertRulesToJson(rules: rules), forKey: Self.storageKey) }
    }
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Une demande d'ouverture des réglages, venue d'un clic sur une notification.
    /// Les vues de la barre des menus l'observent et ouvrent la fenêtre.
    private(set) var settingsRequest: SettingsRequest?

    struct SettingsRequest: Equatable {
        let tab: String
        let id = UUID()
    }

    @ObservationIgnored private let engine = AlertEngine()
    private static let storageKey = "alertRules"
    /// Valeur spéciale de « onglet » : ouvre la fenêtre de mise à jour.
    static let updateWindowTab = "update-window"
    /// Clé, dans la notification, de l'onglet des réglages à ouvrir.
    private nonisolated static let userInfoTabKey = "settingsTab"
    private nonisolated static let logger = Logger(subsystem: "ch.latifcodess.pulse", category: "alerts")

    override init() {
        rules = UserDefaults.standard.string(forKey: Self.storageKey).map { alertRulesFromJson(json: $0) }
            ?? defaultAlertRules()
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await requestAuthorizationIfNeeded() }
    }

    /// À appeler à chaque nouvel état d'un service.
    func handle(service: AiService, state: AiState) {
        let now = Int64(Date.now.timeIntervalSince1970)
        for event in engine.evaluate(service: service, state: state, rules: rules, now: now) {
            post(event)
        }
    }

    func resetRules() {
        rules = defaultAlertRules()
    }

    func addRule(_ kind: AlertKind) {
        rules.append(AlertRule(id: UUID().uuidString, enabled: true, service: nil, kind: kind))
    }

    // MARK: - Autorisation

    func reloadAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        await reloadAuthorization()
        guard authorization == .notDetermined, rules.contains(where: \.enabled) else { return }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Autorisation des notifications : \(error.localizedDescription, privacy: .public)")
        }
        await reloadAuthorization()
    }

    func openSystemSettings() {
        let url = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=ch.latifcodess.pulse"
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Pulse"
        content.body = "Les notifications fonctionnent."
        content.sound = .default
        deliver(content, identifier: "test")
    }

    /// Une notification à propos des mises à jour de Pulse (voir Updater).
    /// Un clic ouvre la fenêtre de mise à jour.
    func notifyAboutUpdate(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [Self.userInfoTabKey: Self.updateWindowTab]
        deliver(content, identifier: "update")
    }

    // MARK: - Envoi

    private func post(_ event: AlertEvent) {
        let service = event.service
        let content = UNMutableNotificationContent()
        content.sound = .default
        var identifier = "\(event.ruleId).\(service.storageKey)"

        switch event.kind {
        case .threshold(let label, let percent, let threshold, let resetsAt):
            content.title = "\(service.title) : \(UsageFormat.percent(percent)) utilisé"
            var body = "« \(label) » a dépassé le seuil de \(UsageFormat.percent(threshold))."
            if resetsAt != nil {
                body += " " + UsageFormat.reset(resetsAt, now: .now) + "."
            }
            content.body = body
            identifier += ".\(label)"
        case .available(let label, let previousPercent):
            content.title = "\(service.title) de nouveau disponible"
            content.body = "« \(label) » repart à zéro (la fenêtre précédente avait atteint \(UsageFormat.percent(previousPercent)))."
            identifier += ".\(label)"
        case .projection(let label, let percent, let fullAt):
            let minutes = max(0, Int((Double(fullAt) - Date.now.timeIntervalSince1970) / 60))
            content.title = "\(service.title) : limite bientôt atteinte"
            let time = Date(timeIntervalSince1970: TimeInterval(fullAt))
                .formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "fr_FR")))
            content.body = "Au rythme actuel, « \(label) » (\(UsageFormat.percent(percent))) atteindra 100 % "
                + "vers \(time), dans \(minutes) min."
            identifier += ".\(label)"
        case .expired:
            content.title = "\(service.title) : session expirée"
            content.body = "\(service.expiredHint) Cliquez pour ouvrir les réglages."
            content.userInfo = [Self.userInfoTabKey: service.storageKey]
        }
        deliver(content, identifier: identifier)
    }

    /// Une notification avec le même identifiant remplace la précédente.
    private func deliver(_ content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Notification non envoyée : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Affiche la notification même quand Pulse est l'app active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Clic sur une notification « Session expirée » : ouvre les réglages.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let tab = response.notification.request.content.userInfo[Self.userInfoTabKey] as? String else {
            return
        }
        await MainActor.run {
            settingsRequest = SettingsRequest(tab: tab)
        }
    }
}
