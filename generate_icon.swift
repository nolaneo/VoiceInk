#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Shared waveform points (from the SVG)
let svgPoints: [(CGFloat, CGFloat)] = [
    (0.5, 12.0), (1.0, 12.0), (2.0, 12.0),
    (3.0, 12.0), (3.5, 11.5), (4.0, 10.5), (4.3, 9.8),
    (4.8, 11.0), (5.2, 12.5), (5.5, 14.2), (5.8, 15.2),
    (6.2, 14.0), (6.5, 12.5), (6.8, 10.5), (7.0, 9.0), (7.2, 7.8),
    (7.5, 7.0), (7.8, 6.5), (8.2, 6.2),
    (8.5, 7.0), (8.8, 8.5), (9.0, 10.0), (9.3, 12.0), (9.5, 13.5),
    (9.8, 15.0), (10.0, 16.0), (10.2, 16.5),
    (10.5, 16.2), (10.8, 15.0), (11.0, 13.5), (11.3, 11.5),
    (11.5, 10.0), (11.8, 8.5), (12.0, 7.5),
    (12.2, 6.8), (12.5, 6.2), (12.8, 6.0),
    (13.0, 6.5), (13.2, 7.5), (13.5, 9.0), (13.8, 11.0),
    (14.0, 12.5), (14.2, 14.0), (14.5, 15.5), (14.8, 16.5), (15.0, 17.0),
    (15.2, 16.5), (15.5, 15.0), (15.8, 13.5), (16.0, 12.0),
    (16.2, 11.0), (16.5, 10.0),
    (16.8, 9.5), (17.0, 9.2), (17.2, 9.5), (17.5, 10.5),
    (17.8, 11.5), (18.0, 12.5), (18.2, 13.2), (18.5, 13.8),
    (18.8, 13.5), (19.0, 12.8), (19.2, 12.0), (19.5, 11.5),
    (19.8, 11.2), (20.0, 11.5), (20.2, 12.0),
    (20.5, 12.2), (21.0, 12.0), (21.5, 12.0), (22.0, 12.0),
    (23.0, 12.0), (23.5, 12.0),
]

func transformPoints(s: CGFloat, padX: CGFloat, padY: CGFloat) -> [CGPoint] {
    let svgMinX: CGFloat = 0.5, svgMaxX: CGFloat = 23.5
    let svgMinY: CGFloat = 6.0, svgMaxY: CGFloat = 17.0
    let drawW = s - padX * 2
    let drawH = s - padY * 2
    return svgPoints.map { svgX, svgY in
        let x = padX + (svgX - svgMinX) / (svgMaxX - svgMinX) * drawW
        let y = padY + (1.0 - (svgY - svgMinY) / (svgMaxY - svgMinY)) * drawH
        return CGPoint(x: x, y: y)
    }
}

func createSmoothPath(_ points: [CGPoint]) -> CGMutablePath {
    let path = CGMutablePath()
    guard points.count > 2 else { return path }
    path.move(to: points[0])
    for i in 0..<points.count - 1 {
        let p0 = points[max(i - 1, 0)]
        let p1 = points[i]
        let p2 = points[min(i + 1, points.count - 1)]
        let p3 = points[min(i + 2, points.count - 1)]
        let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: cp1, control2: cp2)
    }
    return path
}

func addWobble(_ points: [CGPoint], amount: CGFloat, seed: CGFloat) -> [CGPoint] {
    return points.enumerated().map { (i, p) in
        let t = CGFloat(i) / CGFloat(points.count)
        let env = sin(t * .pi) * 0.3 + 0.7
        let wx = sin(t * 17 + seed) * amount * env + cos(t * 23 + seed * 1.7) * amount * 0.4 * env
        let wy = sin(t * 13 + seed * 0.8) * amount * env + cos(t * 19 + seed * 2.1) * amount * 0.3 * env
        return CGPoint(x: p.x + wx, y: p.y + wy)
    }
}

// ============================================================
// APP ICON
// ============================================================
func generateAppIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Background
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgColors = [
        CGColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
        CGColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1.0)
    ]
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: bgColors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: s/2, y: s),
                           end: CGPoint(x: s/2, y: 0), options: [])
    ctx.restoreGState()

    let inkMain   = CGColor(red: 0.25, green: 0.50, blue: 0.90, alpha: 1.0)
    let inkBright = CGColor(red: 0.45, green: 0.70, blue: 1.00, alpha: 1.0)
    let inkGlow   = CGColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 0.6)

    let points = transformPoints(s: s, padX: s * 0.12, padY: s * 0.22)
    let baseWidth = s * 0.038

    // Glow
    ctx.saveGState()
    ctx.addPath(createSmoothPath(addWobble(points, amount: s * 0.004, seed: 5)))
    ctx.setStrokeColor(inkGlow)
    ctx.setLineWidth(s * 0.065)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Dark base stroke
    ctx.saveGState()
    ctx.addPath(createSmoothPath(addWobble(points, amount: s * 0.003, seed: 1)))
    ctx.setStrokeColor(CGColor(red: 0.15, green: 0.35, blue: 0.70, alpha: 0.8))
    ctx.setLineWidth(baseWidth * 1.4)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Main stroke
    ctx.saveGState()
    ctx.addPath(createSmoothPath(addWobble(points, amount: s * 0.005, seed: 2)))
    ctx.setStrokeColor(inkMain)
    ctx.setLineWidth(baseWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Highlight
    ctx.saveGState()
    let hlPoints = addWobble(points, amount: s * 0.003, seed: 3).map {
        CGPoint(x: $0.x, y: $0.y + s * 0.004)
    }
    ctx.addPath(createSmoothPath(hlPoints))
    ctx.setStrokeColor(inkBright)
    ctx.setLineWidth(baseWidth * 0.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// ============================================================
// MENU BAR ICON (template: black on transparent)
// ============================================================
func generateMenuBarIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Transparent background — nothing to draw

    let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)

    let points = transformPoints(s: s, padX: s * 0.10, padY: s * 0.20)
    let baseWidth = s * 0.055

    // Single solid stroke with slight wobble for ink feel
    ctx.saveGState()
    ctx.addPath(createSmoothPath(addWobble(points, amount: s * 0.004, seed: 2)))
    ctx.setStrokeColor(black)
    ctx.setLineWidth(baseWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, path: String, size: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: CGFloat(size), height: CGFloat(size))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

// Generate app icons
let appIconBase = "/Users/eoinnolan/src/VoiceInk/VoiceInk/Assets.xcassets/AppIcon.appiconset"
for size in [1024, 512, 256, 128, 64, 32, 16] {
    print("App icon \(size)x\(size)...")
    savePNG(generateAppIcon(size: size), path: "\(appIconBase)/\(size)-mac.png", size: size)
}

// Generate menu bar icon
let menuBarPath = "/Users/eoinnolan/src/VoiceInk/VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon.png"
print("Menu bar icon 750x750...")
savePNG(generateMenuBarIcon(size: 750), path: menuBarPath, size: 750)

print("Done!")
