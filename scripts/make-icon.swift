// Génère l'icône de Pulse : une onde de pouls sur fond arrondi.
//
// Usage : swift scripts/make-icon.swift <sortie.icns>
//
// Dessine l'icône à chaque taille demandée par macOS, puis les assemble en
// .icns avec iconutil (fourni avec macOS).

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("Usage : swift make-icon.swift <sortie.icns>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])

/// Dessine l'icône dans un carré de `size` pixels. Les coordonnées sont
/// pensées pour 1024 px, puis mises à l'échelle.
func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    // Fond : carré arrondi à la taille standard des icônes macOS (824 px sur
    // 1024, avec une marge pour l'ombre).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(tilePath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(srgbRed: 0.16, green: 0.17, blue: 0.42, alpha: 1).cgColor,
            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.17, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Quadrillage discret, comme sur un moniteur cardiaque.
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.06).cgColor)
    context.setLineWidth(4)
    for position in stride(from: 100.0, through: 924.0, by: 103.0) {
        context.move(to: CGPoint(x: position, y: 100))
        context.addLine(to: CGPoint(x: position, y: 924))
        context.move(to: CGPoint(x: 100, y: position))
        context.addLine(to: CGPoint(x: 924, y: position))
    }
    context.strokePath()

    // L'onde : ligne plate, petite bosse, pic, creux, retour, petite bosse.
    let points: [CGPoint] = [
        CGPoint(x: 160, y: 500), CGPoint(x: 330, y: 500), CGPoint(x: 375, y: 560),
        CGPoint(x: 420, y: 500), CGPoint(x: 460, y: 500), CGPoint(x: 520, y: 760),
        CGPoint(x: 590, y: 270), CGPoint(x: 640, y: 540), CGPoint(x: 670, y: 500),
        CGPoint(x: 730, y: 500), CGPoint(x: 770, y: 545), CGPoint(x: 810, y: 500),
        CGPoint(x: 864, y: 500),
    ]
    let wave = CGMutablePath()
    wave.addLines(between: points)

    let stroke = wave.copy(strokingWithWidth: 50, lineCap: .round, lineJoin: .round, miterLimit: 10)
    // Halo lumineux sous la ligne.
    context.saveGState()
    context.setShadow(offset: .zero, blur: 40, color: NSColor(srgbRed: 0.3, green: 0.9, blue: 1, alpha: 0.9).cgColor)
    context.addPath(stroke)
    context.setFillColor(NSColor(srgbRed: 0.3, green: 0.9, blue: 1, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()
    // Dégradé cyan → rose le long de la ligne.
    context.addPath(stroke)
    context.clip()
    let line = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(srgbRed: 0.35, green: 0.92, blue: 1, alpha: 1).cgColor,
            NSColor(srgbRed: 1, green: 0.38, blue: 0.62, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(line, start: CGPoint(x: 130, y: 512), end: CGPoint(x: 894, y: 512), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Les tailles d'un .iconset : chaque taille en 1x et en 2x (Retina).
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Pulse-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: base * factor).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil a échoué\n".data(using: .utf8)!)
    exit(1)
}
print("Icône écrite : \(output.path)")
