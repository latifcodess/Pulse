import AppKit
import Observation
import PulseCore
import SwiftUI

/// L'IA affichée dans la fenêtre ; change quand on choisit une autre IA.
@MainActor
@Observable
final class DetailSelection {
    var service: AiService = .claude
}

/// La fenêtre d'une IA (NSPopover), partagée par tous les éléments de la
/// barre : une seule est ouverte à la fois.
@MainActor
final class DetailPopover: NSObject, NSPopoverDelegate {
    private let app: AppModel
    private let popover = NSPopover()
    private let selection = DetailSelection()
    /// Le bouton sous lequel la fenêtre est ouverte.
    private weak var anchor: NSStatusBarButton?
    /// Un clic sur le bouton ferme d'abord la fenêtre (clic à l'extérieur) :
    /// on s'en souvient pour ne pas la rouvrir aussitôt.
    private var closedAt: (button: NSStatusBarButton, date: Date)?
    /// Surveillent les clics pendant que la fenêtre est ouverte (voir
    /// watchOutsideClicks).
    private var clickMonitors: [Any] = []

    init(app: AppModel) {
        self.app = app
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
    }

    /// Ouvre la fenêtre de `service` sous `button`, ou la ferme si elle y est
    /// déjà ouverte. `showsSwitcher` : une rangée de logos pour passer d'une
    /// IA à l'autre (élément regroupé ou compact).
    func toggle(_ service: AiService, from button: NSStatusBarButton, showsSwitcher: Bool) {
        if popover.isShown {
            let same = anchor === button
            popover.performClose(nil)
            if same { return }
        }
        if let closedAt, closedAt.button === button, Date.now.timeIntervalSince(closedAt.date) < 0.3 {
            self.closedAt = nil
            return
        }
        open(service, from: button, showsSwitcher: showsSwitcher)
    }

    /// Ouvre la fenêtre de `service`, sans la refermer si elle est déjà
    /// ouverte (lien du widget) : elle passe simplement à cette IA.
    func show(_ service: AiService, from button: NSStatusBarButton, showsSwitcher: Bool) {
        if popover.isShown, anchor === button {
            selection.service = service
            NSApp.activate()
            return
        }
        if popover.isShown { popover.performClose(nil) }
        open(service, from: button, showsSwitcher: showsSwitcher)
    }

    private func open(_ service: AiService, from button: NSStatusBarButton, showsSwitcher: Bool) {
        selection.service = service
        let controller = NSHostingController(rootView: DetailContainer(
            app: app,
            selection: selection,
            showsSwitcher: showsSwitcher,
            onRefresh: { [weak self] in
                guard let self else { return }
                self.app.model(for: self.selection.service).refreshNow()
            },
            onSettings: { [weak self] in
                guard let self else { return }
                self.popover.performClose(nil)
                WindowRouter.shared.showSettings(tab: self.selection.service.storageKey)
            },
            onUpdate: { [weak self] in
                self?.popover.performClose(nil)
                WindowRouter.shared.show(WindowID.update)
            },
            onQuit: { NSApp.terminate(nil) }))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.hasFullSizeContent = true
        anchor = button
        // Sans icône dans le Dock, l'app doit être active pour que la fenêtre
        // se ferme d'un clic ailleurs.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        watchOutsideClicks()
    }

    /// Ferme la fenêtre au premier clic en dehors. « .transient » ne suffit
    /// pas : macOS ne le fait que si Pulse est l'app active, et depuis
    /// macOS 14 il peut refuser de l'activer (on est alors dans une autre app).
    private func watchOutsideClicks() {
        guard clickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clic dans une autre app (le bureau, une autre fenêtre…).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            clickMonitors.append(global)
        }
        // Clic dans Pulse, hors de la fenêtre (réglages, une autre icône de la barre).
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.popover.contentViewController?.view.window else { return }
                self.close()
            }
            return event
        }) {
            clickMonitors.append(local)
        }
    }

    private func stopWatchingClicks() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    private func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// Libère la vue à la fermeture : rien ne tourne en arrière-plan.
    func popoverDidClose(_ notification: Notification) {
        // Déjà rouverte (sur une autre IA) pendant l'animation de fermeture.
        guard !popover.isShown else { return }
        stopWatchingClicks()
        if let anchor { closedAt = (anchor, .now) }
        anchor = nil
        popover.contentViewController = nil
    }
}

/// La fenêtre, avec au-dessus la rangée des IA suivies si demandé.
private struct DetailContainer: View {
    let app: AppModel
    let selection: DetailSelection
    let showsSwitcher: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onUpdate: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let followed = app.followed
        VStack(spacing: 0) {
            if showsSwitcher, followed.count > 1 {
                ServiceSwitcher(models: followed, selection: selection)
            }
            DetailView(
                app: app,
                model: app.model(for: selection.service),
                onRefresh: onRefresh,
                onSettings: onSettings,
                onUpdate: onUpdate,
                onQuit: onQuit)
            .id(selection.service)
        }
        .background(PulseTheme.background)
    }
}

/// La rangée des IA suivies : logo et %, l'IA affichée en surbrillance.
private struct ServiceSwitcher: View {
    let models: [UsageModel]
    let selection: DetailSelection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(models, id: \.service) { model in
                item(model)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10))
        .frame(width: 360)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseTheme.cardBorder).frame(height: 1)
        }
    }

    private func item(_ model: UsageModel) -> some View {
        let isSelected = model.service == selection.service
        let thresholds = model.settings.thresholds
        return Button {
            withAnimation(.smooth(duration: 0.25)) { selection.service = model.service }
        } label: {
            HStack(spacing: 6) {
                LogoBadge(kind: model.service.logoKind, size: 14)
                if let percent = model.highestPercent {
                    Text(UsageFormat.percent(percent))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PulseTheme.levelColor(percent, warning: thresholds.warning, critical: thresholds.critical))
                        .animatedNumber(percent)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                isSelected ? PulseTheme.controlFill : .clear,
                in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(model.service.title)
        .accessibilityLabel(model.service.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
