import AppKit
import PulseCore
import SwiftUI

/// Rappelle `apply` à chaque changement des valeurs observées qu'il lit
/// (Observation), sur le thread principal.
@MainActor
func observeChanges(_ apply: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in observeChanges(apply) }
    }
}

/// La barre des menus, selon le style choisi (voir MenuBarPreferences) :
/// - un élément par IA (styles A et B, non regroupés) ;
/// - ou un seul élément principal : IA regroupées, style compact, ou l'icône
///   de Pulse quand aucune IA n'est affichée.
@MainActor
final class StatusBarController: NSObject {
    private let app: AppModel
    private let popover: DetailPopover
    private let mainItem: NSStatusItem
    private var serviceItems: [(service: AiService, item: NSStatusItem)] = []
    private let menu = NSMenu()
    private var appearanceObservations: [NSKeyValueObservation] = []

    init(app: AppModel) {
        self.app = app
        popover = DetailPopover(app: app)
        // Les éléments s'ajoutent de droite à gauche : l'élément principal à
        // droite, puis les IA, la première finissant la plus à gauche.
        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Le nom d'enregistrement garde la place choisie avec ⌘ d'un lancement à l'autre.
        mainItem.autosaveName = "pulse.main"
        configure(mainItem, action: #selector(mainClicked(_:)), label: "Pulse")
        for model in app.services.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "pulse.\(model.service.storageKey)"
            configure(item, action: #selector(serviceClicked(_:)), label: model.service.title)
            serviceItems.insert((model.service, item), at: 0)
        }
        setUpMenu()

        // Redessine la barre quand une valeur ou un réglage change…
        observeChanges { [weak self] in self?.render() }
        observeRequests()
    }

    private func configure(_ item: NSStatusItem, action: Selector, label: String) {
        guard let button = item.button else { return }
        button.target = self
        button.action = action
        button.setAccessibilityLabel(label)
        // … ou quand la barre des menus passe du clair au sombre.
        appearanceObservations.append(button.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.render() }
        })
    }

    // MARK: - Dessin

    private func render() {
        let prefs = app.menuBar
        let shown = app.services.filter(prefs.showsInBar)
        let grouped = prefs.style == .compact || prefs.groupsServices

        // Un élément par IA.
        var anyServiceShown = false
        for (service, item) in serviceItems {
            let model = app.model(for: service)
            let visible = !grouped && shown.contains { $0 === model }
            item.isVisible = visible
            if visible, let button = item.button {
                anyServiceShown = true
                draw(.single(BarEntry(model), prefs.style), in: button)
            }
        }

        // L'élément principal.
        var content: BarContent?
        if grouped, !shown.isEmpty {
            if prefs.style == .compact {
                let known = shown.filter { $0.highestPercent != nil }
                if !known.isEmpty, let nearest = app.nearest(among: known) {
                    content = .compact(CompactEntry(nearest))
                }
            } else {
                content = .group(shown.map(BarEntry.init), prefs.style)
            }
        }
        mainItem.isVisible = content != nil || !anyServiceShown
        // Aucune IA suivie : le clic ouvre le menu de Pulse.
        mainItem.menu = app.followed.isEmpty ? menu : nil
        guard let button = mainItem.button else { return }
        if let content {
            draw(content, in: button)
        } else {
            drawPulseIcon(in: button)
        }
    }

    private func draw(_ content: BarContent, in button: NSStatusBarButton) {
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = BarContentView(content: content, palette: BarPalette(isDark: isDark))
        if let image = view.image() {
            button.image = image
        }
        button.toolTip = view.description
        button.setAccessibilityValue(view.description)
    }

    /// L'icône de Pulse : aucune IA suivie, ou toutes masquées sous le seuil.
    private func drawPulseIcon(in button: NSStatusBarButton) {
        button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Pulse")
        button.toolTip = app.followed.isEmpty ? "Pulse : aucune IA suivie" : "Pulse"
        button.setAccessibilityValue(nil)
    }

    // MARK: - Clics

    /// Élément regroupé ou compact : la fenêtre de l'IA la plus proche de sa
    /// limite, avec la rangée des IA pour passer à une autre.
    @objc private func mainClicked(_ sender: NSStatusBarButton) {
        let shown = app.services.filter(app.menuBar.showsInBar)
        guard let target = app.nearest(among: shown.isEmpty ? nil : shown) else { return }
        popover.toggle(target.service, from: sender, showsSwitcher: true)
    }

    /// Ouvre la fenêtre d'une IA (clic sur le widget), sous son icône si elle
    /// en a une, sinon sous l'élément principal. Une IA non suivie ouvre ses
    /// réglages, pour pouvoir la suivre.
    func showDetail(for service: AiService) {
        guard app.model(for: service).isEnabled else {
            WindowRouter.shared.showSettings(tab: service.storageKey)
            return
        }
        if let item = serviceItems.first(where: { $0.service == service })?.item, item.isVisible,
            let button = item.button
        {
            popover.show(service, from: button, showsSwitcher: false)
        } else if let button = mainItem.button {
            popover.show(service, from: button, showsSwitcher: true)
        }
    }

    @objc private func serviceClicked(_ sender: NSStatusBarButton) {
        guard let service = serviceItems.first(where: { $0.item.button === sender })?.service else { return }
        popover.toggle(service, from: sender, showsSwitcher: false)
    }

    // MARK: - Menu (aucune IA suivie)

    private func setUpMenu() {
        let title = NSMenuItem(title: "Aucune IA suivie", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(menuItem("Réglages…", #selector(openSettings), key: ","))
        menu.addItem(menuItem("Rechercher les mises à jour…", #selector(checkForUpdates), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quitter Pulse", #selector(quit), key: "q"))
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() {
        WindowRouter.shared.showSettings(tab: SettingsTab.general)
    }

    @objc private func checkForUpdates() {
        WindowRouter.shared.show(WindowID.update)
        Task { await app.updater.check(.user) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Fenêtres demandées hors d'une vue

    /// Clic sur une notification, ou mise à jour trouvée au lancement.
    private func observeRequests() {
        var lastSettings = app.alertCenter.settingsRequest
        var lastUpdate = app.updater.windowRequest
        observeChanges { [weak self] in
            guard let self else { return }
            let settings = self.app.alertCenter.settingsRequest
            let update = self.app.updater.windowRequest
            if let settings, settings != lastSettings {
                if settings.tab == AlertCenter.updateWindowTab {
                    WindowRouter.shared.show(WindowID.update)
                } else {
                    WindowRouter.shared.showSettings(tab: settings.tab)
                }
            }
            if update != nil, update != lastUpdate {
                WindowRouter.shared.show(WindowID.update)
            }
            lastSettings = settings
            lastUpdate = update
        }
    }
}
