import AppKit
import PulseCore
import SwiftUI

/// La fenêtre Réglages (maquettes design/pulse-maquettes/Settings.dc.html et
/// SettingsGeneral.dc.html) : barre latérale avec Général, Alertes et les IA,
/// et la page choisie à droite.
struct SettingsView: View {
    let app: AppModel

    /// La page affichée : "general", "alerts" ou la clé d'une IA. La fenêtre
    /// d'une IA le change pour ouvrir directement sa page.
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.general

    var body: some View {
        // Deux colonnes fixes plutôt que NavigationSplitView : sur macOS 26,
        // sa barre latérale flotte dans un panneau vitré, loin de la maquette.
        HStack(spacing: 0) {
            SettingsSidebar(app: app, selection: $tab)
                .frame(width: 210)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(PulseTheme.cardBorder).frame(width: 1)
                }
            ScrollView {
                page
                    .padding(EdgeInsets(top: 22, leading: 28, bottom: 24, trailing: 28))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PulseTheme.settingsBackground)
        }
        .ignoresSafeArea()
        .frame(minWidth: 780)
        .foregroundStyle(PulseTheme.text)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case SettingsTab.alerts:
            AlertsSettingsPage(alerts: app.alertCenter, services: app.services.map(\.service))
        default:
            if let model = app.services.first(where: { $0.service.storageKey == tab }) {
                ServiceSettingsPage(app: app, model: model)
                    .id(tab)
            } else {
                GeneralSettingsPage(app: app)
            }
        }
    }
}

enum SettingsTab {
    static let storageKey = "settingsTab"
    static let general = "general"
    static let alerts = "alerts"
}

// MARK: - Barre latérale

private struct SettingsSidebar: View {
    let app: AppModel
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // La place des boutons de la fenêtre (fermer, réduire).
            Color.clear.frame(height: 32)

            row(SettingsTab.general, title: "Général") {
                SymbolBadge(systemImage: "gearshape.fill", color: Color(hex: 0x636366))
            }
            row(SettingsTab.alerts, title: "Alertes") {
                SymbolBadge(systemImage: "bell.fill", color: PulseTheme.warning)
            }

            Text("IA suivies".uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.44)
                .foregroundStyle(PulseTheme.tertiary)
                .padding(EdgeInsets(top: 16, leading: 10, bottom: 6, trailing: 10))
                .accessibilityAddTraits(.isHeader)

            ForEach(app.services, id: \.service) { model in
                let isConnected = model.isEnabled && model.isSignedIn
                row(model.service.storageKey, title: model.service.title, trailing: {
                    StatusDot(color: isConnected ? PulseTheme.connected : PulseTheme.disconnected, size: 7)
                        .accessibilityLabel(isConnected ? "connecté" : (model.isEnabled ? "non connecté" : "non suivi"))
                }) {
                    LogoBadge(kind: model.service.logoKind, size: 16)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 14, leading: 10, bottom: 14, trailing: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PulseTheme.sidebar)
        .ignoresSafeArea()
    }

    private func row(
        _ tab: String, title: String,
        @ViewBuilder trailing: () -> some View = { EmptyView() },
        @ViewBuilder icon: () -> some View
    ) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 10) {
                icon()
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(PulseTheme.text)
                Spacer(minLength: 4)
                trailing()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isSelected ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Pastille de 22 pt avec un symbole blanc (Général, Alertes).
private struct SymbolBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Général

private struct GeneralSettingsPage: View {
    let app: AppModel

    var body: some View {
        @Bindable var menuBar = app.menuBar
        @Bindable var launchAtLogin = app.launchAtLogin
        VStack(alignment: .leading, spacing: 16) {
            PageTitle("Général")

            SettingsSection(title: "Style dans la barre des menus") {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(MenuBarStyle.allCases) { style in
                        StyleCard(style: style, isSelected: menuBar.style == style) {
                            withAnimation(.smooth(duration: 0.2)) { menuBar.style = style }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            ColorSection(menuBar: menuBar)

            SettingsSection(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16), spacing: 0) {
                SettingsRow(
                    title: "Regrouper les IA dans un seul élément",
                    subtitle: menuBar.style == .compact
                        ? "Le style Compact affiche toujours un seul élément"
                        : "Désactivé : chaque IA a sa propre icône, déplaçable avec ⌘"
                ) {
                    PulseSwitch(isOn: $menuBar.groupsServices, label: "Regrouper les IA")
                        .disabled(menuBar.style == .compact)
                }
                SettingsRow(
                    title: "Masquer une IA tant qu'elle est sous",
                    subtitle: "La barre reste discrète jusqu'à ce que ça compte"
                ) {
                    PopupMenu(
                        options: MenuBarPreferences.hideOptions.map { ($0, $0 == 0 ? "Jamais" : "\($0) %") },
                        selection: $menuBar.hideBelow,
                        label: "Seuil de masquage")
                }
                SettingsRow(
                    title: "Ouvrir Pulse au démarrage",
                    subtitle: launchAtLogin.needsApproval
                        ? "macOS attend votre accord dans Réglages Système › Général › Ouverture."
                        : nil,
                    showsDivider: launchAtLogin.errorMessage == nil
                ) {
                    HStack(spacing: 10) {
                        if launchAtLogin.needsApproval {
                            Button("Ouvrir les Réglages Système") { launchAtLogin.openSystemSettings() }
                                .buttonStyle(.pulse)
                        }
                        PulseSwitch(isOn: $launchAtLogin.isEnabled, label: "Ouvrir au démarrage")
                    }
                }
                if let error = launchAtLogin.errorMessage {
                    SettingsNote(error, color: PulseTheme.warningText)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(PulseTheme.cardBorder).frame(height: 1) }
                }
                SettingsRow(
                    title: "Afficher sur l'écran verrouillé",
                    subtitle: LockScreenWindow.isAvailable
                        ? "Expérimental : le logo, le % et la projection de chaque IA, sous l'horloge. Visible par toute personne devant le Mac."
                        : "Non disponible sur cette version de macOS",
                    showsDivider: false
                ) {
                    PulseSwitch(isOn: $menuBar.showsOnLockScreen, label: "Afficher sur l'écran verrouillé")
                        .disabled(!LockScreenWindow.isAvailable)
                }
                .opacity(LockScreenWindow.isAvailable ? 1 : 0.6)
            }

            UpdatesSection(updater: app.updater)
        }
        .onAppear { launchAtLogin.reload() }
    }
}

/// La couleur des pourcentages, barres et anneaux sous le seuil orange :
/// une pastille par couleur proposée, ou une couleur personnalisée.
private struct ColorSection: View {
    @Bindable var menuBar: MenuBarPreferences

    var body: some View {
        let isPreset = NormalColor.presets.contains { $0.hex == menuBar.normalColorHex }
        SettingsSection(title: "Couleur") {
            HStack(spacing: 8) {
                ForEach(NormalColor.presets, id: \.hex) { preset in
                    swatch(preset.hex, name: preset.name)
                }
            }
            HStack(spacing: 10) {
                ColorPicker(selection: customColor, supportsOpacity: false) {
                    Text("Personnalisée").font(.system(size: 13))
                }
                .fixedSize()
                if !isPreset {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PulseTheme.secondary)
                }
                Spacer()
                if menuBar.normalColorHex != NormalColor.defaultHex {
                    Button("Couleur par défaut") { menuBar.normalColorHex = NormalColor.defaultHex }
                        .buttonStyle(.pulse)
                }
            }
            SettingsNote("Pour les pourcentages, les barres et les anneaux sous le seuil orange, dans la barre des menus, les fenêtres et les widgets. L'orange et le rouge restent ceux des seuils.")
        }
    }

    private func swatch(_ hex: UInt32, name: String) -> some View {
        let isSelected = menuBar.normalColorHex == hex
        return Button {
            withAnimation(.smooth(duration: 0.2)) { menuBar.normalColorHex = hex }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .padding(3)
                .overlay {
                    Circle().strokeBorder(isSelected ? PulseTheme.text : .clear, lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Le sélecteur de couleurs de macOS, enregistré en 0xRRGGBB.
    private var customColor: Binding<Color> {
        Binding {
            Color(hex: menuBar.normalColorHex)
        } set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let channel = { (value: CGFloat) in UInt32((min(max(value, 0), 1) * 255).rounded()) }
            menuBar.normalColorHex = channel(rgb.redComponent) << 16 | channel(rgb.greenComponent) << 8 | channel(rgb.blueComponent)
        }
    }
}

/// Une carte de style : aperçu sur fond noir, nom et description. Bordure
/// bleue de 2 pt quand elle est choisie.
private struct StyleCard: View {
    let style: MenuBarStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                StylePreview(style: style)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: 0x0E0E10), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(style.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                isSelected ? PulseTheme.accent.opacity(0.08) : Color.white.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? PulseTheme.accent : Color.white.opacity(0.08), lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// La barre des menus en miniature, avec les valeurs de la maquette.
private struct StylePreview: View {
    let style: MenuBarStyle

    var body: some View {
        HStack(spacing: 6) {
            switch style {
            case .logoPercent:
                HStack(spacing: 2) {
                    LogoBadge(kind: .claude, size: 9)
                    Text("78%").foregroundStyle(PulseTheme.warning)
                }
                HStack(spacing: 2) {
                    LogoBadge(kind: .chatGpt, size: 9)
                    Text("42%")
                }
                Text("+2")
                    .fontWeight(.medium)
                    .foregroundStyle(PulseTheme.secondary)
            case .rings:
                UsageRing(percent: 78, color: PulseTheme.warning, size: 14)
                UsageRing(percent: 42, color: PulseTheme.normal, size: 14)
                UsageRing(percent: 12, color: PulseTheme.normal, size: 14)
            case .compact:
                PulseGlyph()
                    .stroke(PulseTheme.warning, style: StrokeStyle(lineWidth: 2.6 * 13 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 13)
                Text("78%").foregroundStyle(PulseTheme.warning)
                Text("· 15:32")
                    .fontWeight(.medium)
                    .foregroundStyle(PulseTheme.secondary)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Mises à jour

private struct UpdatesSection: View {
    @Bindable var updater: Updater

    var body: some View {
        SettingsSection(title: "Mises à jour", padding: EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16), spacing: 0) {
            SettingsRow(title: "Version installée") {
                Text(updater.currentVersion)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(PulseTheme.secondary)
            }
            .padding(.top, 4)
            SettingsRow(title: "Rechercher automatiquement", subtitle: "Au lancement, puis chaque jour") {
                PulseSwitch(isOn: $updater.automaticChecks, label: "Rechercher automatiquement")
            }
            status
            SettingsNote("Les mises à jour viennent des releases GitHub de Pulse. Chaque téléchargement est vérifié (empreinte SHA-256) avant l'installation.")
                .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updater.phase {
        case .available(let info):
            VStack(alignment: .leading, spacing: 8) {
                Label("Pulse \(info.version) est disponible", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PulseTheme.accent)
                if !info.notes.isEmpty {
                    Text(info.notes.replacingOccurrences(of: "\r", with: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.secondary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button("Installer et relancer") {
                        Task { await updater.install(info) }
                    }
                    .buttonStyle(.pulsePrimary)
                    if let page = URL(string: info.pageUrl), !info.pageUrl.isEmpty {
                        Link("Voir sur GitHub", destination: page)
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(PulseTheme.cardBorder).frame(height: 1) }
        case .downloading(let info):
            progressRow("Téléchargement de Pulse \(info.version)…")
        case .installing:
            progressRow("Installation… Pulse va redémarrer.")
        default:
            let text = statusText
            SettingsRow(title: text.title, subtitle: text.subtitle) {
                if case .checking = updater.phase {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Rechercher maintenant") {
                        Task { await updater.check(.user) }
                    }
                    .buttonStyle(.pulse)
                }
            }
        }
    }

    private func progressRow(_ text: String) -> some View {
        SettingsRow(title: text) {
            ProgressView().controlSize(.small)
        }
    }

    private var statusText: (title: String, subtitle: String?) {
        switch updater.phase {
        case .checking:
            return ("Recherche en cours…", nil)
        case .upToDate:
            guard let lastCheck = updater.lastCheck else { return ("Pulse est à jour", nil) }
            return ("Pulse est à jour", "Vérifié à \(UsageFormat.hourMinute(lastCheck))")
        case .failed(let message):
            return ("La recherche a échoué", message)
        default:
            return ("Pas encore recherché", nil)
        }
    }
}
