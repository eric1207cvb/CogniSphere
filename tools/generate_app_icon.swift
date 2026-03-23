import AppKit

let outputDirectory = URL(fileURLWithPath: "/Users/eric1207cvb/Desktop/CogniSphere/CogniSphere/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let canvasSize = CGSize(width: 1024, height: 1024)

enum IconVariant: String, CaseIterable {
    case primary = "icon-primary.png"
    case dark = "icon-dark.png"
    case tinted = "icon-tinted.png"
}

func drawRoundedRect(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, color: NSColor) {
    color.setFill()
    path.fill()
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func gradientBackground(for variant: IconVariant, in rect: CGRect) {
    let colors: [NSColor]
    switch variant {
    case .primary:
        colors = [
            NSColor(calibratedRed: 0.07, green: 0.18, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.37, blue: 0.39, alpha: 1),
            NSColor(calibratedRed: 0.89, green: 0.70, blue: 0.39, alpha: 1)
        ]
    case .dark:
        colors = [
            NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.21, blue: 0.24, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.58, blue: 0.60, alpha: 1)
        ]
    case .tinted:
        colors = [
            NSColor.clear,
            NSColor.clear
        ]
    }

    guard variant != .tinted else { return }

    let gradient = NSGradient(colors: colors)!
    gradient.draw(in: rect, angle: -52)

    let glow = NSBezierPath(ovalIn: rect.insetBy(dx: 120, dy: 120).offsetBy(dx: 210, dy: 200))
    let glowGradient = NSGradient(colors: [
        NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.20),
        NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.0)
    ])!
    glowGradient.draw(in: glow, relativeCenterPosition: .zero)
}

func drawOrbitNetwork(for variant: IconVariant, in rect: CGRect) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let orbitColor: NSColor = variant == .tinted
        ? NSColor.black
        : NSColor(calibratedRed: 0.93, green: 0.97, blue: 0.98, alpha: 0.88)

    let secondaryOrbitColor: NSColor = variant == .tinted
        ? NSColor(calibratedWhite: 0.08, alpha: 1)
        : NSColor(calibratedRed: 0.74, green: 0.89, blue: 0.93, alpha: 0.42)

    for scale in [1.0, 0.78, 0.58] {
        let oval = NSBezierPath(ovalIn: CGRect(
            x: center.x - 220 * scale,
            y: center.y - 270 * scale,
            width: 440 * scale,
            height: 540 * scale
        ))
        stroke(oval, color: secondaryOrbitColor, width: 9 * scale)
    }

    let latitudes: [CGFloat] = [-180, -80, 40, 155]
    for offset in latitudes {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - 238, y: center.y + offset))
        path.curve(to: CGPoint(x: center.x + 238, y: center.y + offset),
                   controlPoint1: CGPoint(x: center.x - 110, y: center.y + offset + 58),
                   controlPoint2: CGPoint(x: center.x + 110, y: center.y + offset - 58))
        stroke(path, color: secondaryOrbitColor, width: 8)
    }

    let meridian = NSBezierPath()
    meridian.move(to: CGPoint(x: center.x, y: center.y - 290))
    meridian.curve(to: CGPoint(x: center.x, y: center.y + 290),
                   controlPoint1: CGPoint(x: center.x - 120, y: center.y - 140),
                   controlPoint2: CGPoint(x: center.x + 120, y: center.y + 140))
    stroke(meridian, color: orbitColor, width: 10)

    let diagonal = NSBezierPath()
    diagonal.move(to: CGPoint(x: center.x - 200, y: center.y - 190))
    diagonal.curve(to: CGPoint(x: center.x + 200, y: center.y + 200),
                   controlPoint1: CGPoint(x: center.x - 60, y: center.y - 270),
                   controlPoint2: CGPoint(x: center.x + 90, y: center.y + 300))
    stroke(diagonal, color: orbitColor, width: 10)

    let bridge = NSBezierPath()
    bridge.move(to: CGPoint(x: center.x - 255, y: center.y + 55))
    bridge.curve(to: CGPoint(x: center.x + 220, y: center.y - 70),
                 controlPoint1: CGPoint(x: center.x - 120, y: center.y - 28),
                 controlPoint2: CGPoint(x: center.x + 105, y: center.y + 10))
    stroke(bridge, color: orbitColor, width: 10)
}

func drawNodes(for variant: IconVariant, in rect: CGRect) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let nodes: [(CGPoint, CGFloat, NSColor)] = [
        (CGPoint(x: center.x, y: center.y - 284), 26, NSColor(calibratedRed: 0.99, green: 0.81, blue: 0.42, alpha: 1)),
        (CGPoint(x: center.x + 228, y: center.y - 72), 24, NSColor(calibratedRed: 0.95, green: 0.47, blue: 0.40, alpha: 1)),
        (CGPoint(x: center.x - 214, y: center.y + 74), 24, NSColor(calibratedRed: 0.39, green: 0.84, blue: 0.68, alpha: 1)),
        (CGPoint(x: center.x + 48, y: center.y + 250), 24, NSColor(calibratedRed: 0.43, green: 0.74, blue: 0.99, alpha: 1))
    ]

    for (point, radius, color) in nodes {
        let drawColor = variant == .tinted ? NSColor.black : color
        let haloColor = variant == .tinted ? NSColor.black.withAlphaComponent(0.12) : drawColor.withAlphaComponent(0.18)

        let halo = NSBezierPath(ovalIn: CGRect(x: point.x - radius - 12, y: point.y - radius - 12, width: (radius + 12) * 2, height: (radius + 12) * 2))
        fill(halo, color: haloColor)

        let circle = NSBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        fill(circle, color: drawColor)
    }
}

func drawCore(for variant: IconVariant, in rect: CGRect) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let coreColor = variant == .tinted ? NSColor.black : NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 0.96)
    let accent = variant == .tinted ? NSColor.black : NSColor(calibratedRed: 0.93, green: 0.97, blue: 0.98, alpha: 0.55)

    let core = NSBezierPath(ovalIn: CGRect(x: center.x - 54, y: center.y - 54, width: 108, height: 108))
    fill(core, color: coreColor)

    let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 88, y: center.y - 88, width: 176, height: 176))
    stroke(ring, color: accent, width: 10)
}

func makeImage(for variant: IconVariant) -> NSImage {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    bitmap.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let rect = CGRect(origin: .zero, size: canvasSize)

    if variant == .tinted {
        NSColor.clear.setFill()
        rect.fill()
    } else {
        fill(drawRoundedRect(in: rect, radius: 226), color: .clear)
        gradientBackground(for: variant, in: rect)
    }

    drawOrbitNetwork(for: variant, in: rect)
    drawNodes(for: variant, in: rect)
    drawCore(for: variant, in: rect)

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: canvasSize)
    image.addRepresentation(bitmap)
    return image
}

func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for variant in IconVariant.allCases {
    let fileURL = outputDirectory.appendingPathComponent(variant.rawValue)
    let image = makeImage(for: variant)
    guard let data = pngData(from: image) else {
        fputs("Failed to generate \(variant.rawValue)\n", stderr)
        exit(1)
    }
    try data.write(to: fileURL)
    print("Wrote \(fileURL.path)")
}
