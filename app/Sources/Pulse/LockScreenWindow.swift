import AppKit
import OSLog
import PulseCore
import SwiftUI

// EXPÉRIMENTAL — Afficher les IA sur l'écran verrouillé.
//
// macOS ne permet à aucune app de dessiner au-dessus de l'écran verrouillé.
// Comme les apps de type « notch », on passe par SkyLight, le framework privé
// qui parle au WindowServer : on crée un « espace » (space) placé au-dessus de
// l'écran verrouillé, et on y range notre fenêtre. Tout le code privé est dans
// ce fichier ; si une fonction manque, l'option est simplement indisponible.

// MARK: - Fonctions privées de SkyLight

/// Les fonctions privées utilisées, chargées une fois avec dlopen/dlsym.
/// dlsym vérifie seulement que le nom existe, pas sa signature : celles
/// ci-dessous viennent des apps open source qui les utilisent.
private struct SkyLight {
    /// La connexion de l'app au WindowServer.
    typealias MainConnectionID = @convention(c) () -> Int32
    /// Crée un espace : (connexion, type, options) → identifiant.
    typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    /// Place un espace à un niveau absolu (au-dessus de l'écran verrouillé).
    typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    /// Affiche ou masque des espaces : (connexion, [identifiants]).
    typealias ShowHideSpaces = @convention(c) (Int32, CFArray) -> Int32
    /// Range des fenêtres dans un espace : (connexion, espace, [n° de fenêtres], masque).
    typealias AddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    let mainConnectionID: MainConnectionID
    let spaceCreate: SpaceCreate
    let spaceSetAbsoluteLevel: SpaceSetAbsoluteLevel
    let showSpaces: ShowHideSpaces
    let hideSpaces: ShowHideSpaces
    let addWindowsAndRemoveFromSpaces: AddWindowsAndRemoveFromSpaces

    private static let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// nil si le framework ou une seule des fonctions manque.
    static func load() -> SkyLight? {
        guard let handle = dlopen(path, RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard
            let mainConnectionID = symbol("SLSMainConnectionID", as: MainConnectionID.self),
            let spaceCreate = symbol("SLSSpaceCreate", as: SpaceCreate.self),
            let spaceSetAbsoluteLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
            let showSpaces = symbol("SLSShowSpaces", as: ShowHideSpaces.self),
            let hideSpaces = symbol("SLSHideSpaces", as: ShowHideSpaces.self),
            let addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsAndRemoveFromSpaces.self)
        else { return nil }
        return SkyLight(
            mainConnectionID: mainConnectionID, spaceCreate: spaceCreate,
            spaceSetAbsoluteLevel: spaceSetAbsoluteLevel, showSpaces: showSpaces,
            hideSpaces: hideSpaces, addWindowsAndRemoveFromSpaces: addWindows)
    }
}

// MARK: - Fenêtre de l'écran verrouillé

/// Affiche les IA suivies sous l'horloge de l'écran verrouillé, si l'option
/// est activée.
///
/// Comme les apps de type « notch », tout est préparé à l'avance : dès que
/// l'option est activée, l'espace est créé et la fenêtre y est rangée,
/// invisible. Une fois l'écran verrouillé, macOS peut refuser de placer une
/// nouvelle fenêtre au-dessus ; on se contente alors de la rendre visible.
@MainActor
final class LockScreenWindow {
    /// Les fonctions de SkyLight, cherchées une seule fois au lancement.
    private static let skyLight = SkyLight.load()

    /// Toutes les fonctions privées sont là : l'option peut être proposée.
    static var isAvailable: Bool { skyLight != nil }

    /// Le niveau absolu de notre espace. Les niveaux connus : 100 assistant de
    /// configuration, 200 agent de sécurité, 300 écran verrouillé, 400 centre
    /// de notifications sur l'écran verrouillé. Il faut donc au moins 400.
    private static let spaceLevel: Int32 = 400
    /// Le « masque » de SLSSpaceAddWindowsAndRemoveFromSpaces : retirer la
    /// fenêtre de tous ses autres espaces.
    private static let removeFromAllSpaces: Int32 = 7

    /// Dans Console.app : processus Pulse, catégorie « lockscreen ».
    private static let logger = Logger(subsystem: "ch.latifcodess.pulse", category: "lockscreen")

    private let app: AppModel
    private var panel: NSPanel?
    private var space: Int32?
    private var isLocked = false

    init(app: AppModel) {
        self.app = app
        Self.logger.notice("SkyLight disponible : \(Self.isAvailable, privacy: .public)")
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.logger.notice("Écran verrouillé")
                self?.isLocked = true
                self?.update()
            }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.logger.notice("Écran déverrouillé")
                self?.isLocked = false
                self?.update()
            }
        }
        // Option activée ou désactivée : on prépare ou on retire la fenêtre.
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.app.menuBar.showsOnLockScreen
            self.update()
        }
    }

    private func update() {
        guard app.menuBar.showsOnLockScreen, let skyLight = Self.skyLight else {
            tearDown()
            return
        }
        prepare(using: skyLight)
        // Visible seulement pendant le verrouillage.
        panel?.alphaValue = isLocked ? 1 : 0
        if let panel { place(panel) }
        Self.logger.notice("Fenêtre \(self.isLocked ? "affichée" : "masquée", privacy: .public)")
    }

    /// Crée l'espace et y range la fenêtre (invisible), une seule fois.
    private func prepare(using skyLight: SkyLight) {
        guard panel == nil else { return }
        let panel = makePanel()
        place(panel)
        panel.alphaValue = 0
        self.panel = panel

        let connection = skyLight.mainConnectionID()
        let newSpace = skyLight.spaceCreate(connection, 1, 0)
        guard newSpace != 0 else {
            Self.logger.error("SLSSpaceCreate a échoué (connexion \(connection, privacy: .public))")
            return
        }
        let level = skyLight.spaceSetAbsoluteLevel(connection, newSpace, Self.spaceLevel)
        let shown = skyLight.showSpaces(connection, [newSpace] as CFArray)
        let added = skyLight.addWindowsAndRemoveFromSpaces(
            connection, newSpace, [panel.windowNumber] as CFArray, Self.removeFromAllSpaces)
        space = newSpace
        // Rangée dans l'espace d'abord, puis affichée (comme SkyLightWindow).
        panel.orderFrontRegardless()
        Self.logger.notice("""
            Espace \(newSpace, privacy: .public) prêt : niveau \(level, privacy: .public), \
            affichage \(shown, privacy: .public), fenêtre \(panel.windowNumber, privacy: .public) \
            rangée \(added, privacy: .public) (0 = réussi)
            """)
    }

    /// Option désactivée : plus de fenêtre ni d'espace visibles.
    private func tearDown() {
        panel?.orderOut(nil)
        panel = nil
        if let space, let skyLight = Self.skyLight {
            _ = skyLight.hideSpaces(skyLight.mainConnectionID(), [space] as CFArray)
        }
        space = nil
    }

    /// Sans bordure ni ombre, transparente, et qui laisse passer tous les clics.
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        // Le plus haut niveau de fenêtre, et visible avant la connexion de
        // l'utilisateur (indispensable sur l'écran verrouillé).
        panel.level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        panel.canBecomeVisibleWithoutLogin = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: LockScreenView(app: app))
        return panel
    }

    /// Centrée, sous l'horloge : environ 26 % de la hauteur depuis le haut.
    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - frame.height * 0.26 - size.height))
    }
}

// MARK: - Contenu

/// « [logo] 78% · limite 15:32 » pour chaque IA suivie, en blanc
/// translucide comme l'horloge ; le % ne se colore qu'au-delà du seuil orange.
private struct LockScreenView: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 24) {
            ForEach(app.followed, id: \.service) { model in
                if let percent = model.highestPercent {
                    let level = model.settings.thresholds.level(for: percent)
                    HStack(spacing: 7) {
                        Image(nsImage: ServiceLogo.image(model.service.logoKind, size: 19))
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 19, height: 19)
                            .accessibilityLabel(model.service.title)
                        Text(UsageFormat.percent(percent))
                            .fontWeight(.semibold)
                            .foregroundStyle(Self.color(level))
                        if let fullAt = model.earliestProjection {
                            Text("· limite \(DetailView.time(fullAt, now: .now))")
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
            }
        }
        .font(.system(size: 18, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.55))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }

    /// Blanc sous le seuil orange, puis orange et rouge.
    private static func color(_ level: UsageLevel) -> Color {
        switch level {
        case .normal: .white.opacity(0.55)
        case .warning: PulseTheme.warning.opacity(0.75)
        case .critical: PulseTheme.critical.opacity(0.75)
        }
    }
}
