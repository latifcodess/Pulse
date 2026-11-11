import AppKit
import SwiftUI

/// La puce d'un service dans la barre des menus : son logo et son %.
struct MenuBarLabel: View {
    let logo: NSImage
    let text: String
    let level: UsageLevel

    var body: some View {
        if let color = level.color {
            // La barre des menus affiche ses éléments en monochrome : pour garder
            // la couleur, on la dessine dans une image non « template ».
            Image(nsImage: Self.coloredImage(logo: logo, text: text, color: color))
        } else {
            HStack {
                Image(nsImage: logo)
                Text(text)
            }
        }
    }

    @MainActor
    static func coloredImage(logo: NSImage, text: String, color: Color) -> NSImage {
        let content = HStack(spacing: 4) {
            Image(nsImage: logo)
                .renderingMode(.template)
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
