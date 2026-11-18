import AppKit
import SwiftUI

// Les contrôles des réglages, dessinés d'après les maquettes
// design/pulse-maquettes/Settings.dc.html et SettingsGeneral.dc.html.

// MARK: - Titres et sections

/// Le titre d'une page : 20 pt, semi-gras.
struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .kerning(-0.2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Une section : fond blanc à 4 %, bordure blanche à 6 %, coins de 10.
struct SettingsSection<Content: View>: View {
    var title: String?
    var padding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                SettingsSectionTitle(title)
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PulseTheme.cardBorder))
    }
}

/// « CONNEXION » : 12 pt, capitales, gris.
struct SettingsSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.48)
            .foregroundStyle(PulseTheme.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Une ligne de liste : titre, sous-titre et contrôle à droite, 48 pt de haut
/// au moins, séparée de la suivante par un trait.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsDivider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(PulseTheme.cardBorder).frame(height: 1)
            }
        }
    }
}

/// Un texte d'aide gris, sur plusieurs lignes.
struct SettingsNote: View {
    let text: String
    var color: Color = PulseTheme.secondary
    init(_ text: String, color: Color = PulseTheme.secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Interrupteur

/// Interrupteur de 38 × 22, vert quand il est activé.
struct PulseSwitch: View {
    @Binding var isOn: Bool
    let label: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? PulseTheme.connected : Color.white.opacity(0.16))
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .padding(2)
                }
                .animation(.smooth(duration: 0.2), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "activé" : "désactivé")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Contrôle segmenté

/// Boutons côte à côte sur un fond blanc à 6 % ; le choix actuel sur #48484A.
struct SegmentedControl<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    /// 28 pt (connexion) ou 26 pt (affichage).
    var height: CGFloat = 28
    /// Les boutons se partagent toute la largeur.
    var fills = false
    var label: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.smooth(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? PulseTheme.text : PulseTheme.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, fills ? 6 : 14)
                        .frame(maxWidth: fills ? .infinity : nil)
                        .frame(height: height)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6).fill(PulseTheme.segmentSelected)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(PulseTheme.segmentTrack, in: RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: !fills, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Menu déroulant

/// Un menu déroulant compact : 28 pt de haut, fond #3A3A3C, coins de 7.
struct PopupMenu<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    let label: String

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .font(.system(size: 12))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(PulseTheme.secondary)
            }
            .foregroundStyle(PulseTheme.text)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(PulseTheme.popupFill, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

// MARK: - Curseur

/// Un seuil en % : titre et valeur colorée, piste de 4 pt, pastille de 16.
struct ThresholdSlider: View {
    let title: String
    @Binding var value: Int
    /// Les valeurs permises.
    let range: ClosedRange<Int>
    var step = 5
    let color: Color
    /// L'échelle de la piste : 0 à 100 % par défaut.
    var scale: ClosedRange<Int> = 0...100
    var unit = "%"

    private var fraction: Double {
        Double(value - scale.lowerBound) / Double(max(scale.upperBound - scale.lowerBound, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) \(unit)")
                    .foregroundStyle(color)
                    .animatedNumber(Double(value))
            }
            .font(.system(size: 13))

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                    Capsule().fill(color).frame(width: width * fraction, height: 4)
                    Circle()
                        .fill(PulseTheme.text)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .offset(x: width * fraction - 8)
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let span = Double(scale.upperBound - scale.lowerBound)
                    set(Double(scale.lowerBound) + Double(drag.location.x / max(width, 1)) * span)
                })
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(Double(value + step))
            case .decrement: set(Double(value - step))
            @unknown default: break
            }
        }
    }

    /// Arrondi au pas, et gardé dans les bornes.
    private func set(_ raw: Double) {
        let stepped = Int((raw / Double(step)).rounded()) * step
        let clamped = min(max(stepped, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
    }
}

// MARK: - Boutons

/// Bouton bordé de blanc à 14 %, 28 pt de haut (« Se déconnecter »). En
/// version principale : fond bleu.
struct PulseButtonStyle: ButtonStyle {
    var isPrimary = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? Color.black.opacity(0.85) : PulseTheme.text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isPrimary ? PulseTheme.accent : Color.white.opacity(configuration.isPressed ? 0.10 : 0))
            }
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.14))
                }
            }
            .opacity(isEnabled ? (configuration.isPressed && isPrimary ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

extension ButtonStyle where Self == PulseButtonStyle {
    static var pulse: PulseButtonStyle { PulseButtonStyle() }
    static var pulsePrimary: PulseButtonStyle { PulseButtonStyle(isPrimary: true) }
}

/// Pastille d'état : 8 pt, verte si connecté.
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}
