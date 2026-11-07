import AppKit
import SwiftUI

/// L'icône et le % dans la barre des menus.
struct MenuBarLabel: View {
    let text: String
    let level: UsageLevel

    var body: some View {
        if let color = level.color {
            // La barre des menus affiche ses éléments en monochrome : pour garder
            // la couleur, on la dessine dans une image non « template ».
            Image(nsImage: Self.coloredImage(text: text, color: color))
        } else {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text(text)
            }
        }
    }

    @MainActor
    static func coloredImage(text: String, color: Color) -> NSImage {
        let content = HStack(spacing: 4) {
            Image(systemName: "waveform.path.ecg")
            Text(text)
        }
        .font(Font(NSFont.menuBarFont(ofSize: 0)))
        .foregroundStyle(color)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false
        return image
    }
}
