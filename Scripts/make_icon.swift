// Draws the app icon and writes AppPackaging/AppIcon.icns.
//
//   swift Scripts/make_icon.swift
//
// The icon is vector drawing, rendered separately for every size the icon set needs, so the
// small sizes stay sharp instead of being scaled down from one bitmap. It follows the macOS
// icon grid: a 824 pt squircle centred on a 1024 pt canvas. Motif: a cloud with a download
// arrow above a photo print. Deliberately no Adobe or LightCraft marks.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
let output = root.appendingPathComponent("AppPackaging/AppIcon.icns")
let preview = root.appendingPathComponent("AppPackaging/AppIcon-1024.png")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// The icon tile: a rounded square with the corner radius of the macOS grid (185 of 824).
func squircle(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
}

/// The cloud outline, in top-left coordinates of the 1024 canvas.
func cloudPath() -> CGPath {
    let path = CGMutablePath()
    path.addEllipse(in: CGRect(x: 395, y: 218, width: 270, height: 270))
    path.addEllipse(in: CGRect(x: 262, y: 318, width: 190, height: 190))
    path.addEllipse(in: CGRect(x: 588, y: 308, width: 200, height: 200))
    // The base stays inside the side lobes, so their curves form the outline without a notch.
    path.addRoundedRect(in: CGRect(x: 300, y: 368, width: 450, height: 140), cornerWidth: 70, cornerHeight: 70)
    return path
}

func arrowPath() -> CGPath {
    let path = CGMutablePath()
    let x: CGFloat = 527
    path.addRoundedRect(in: CGRect(x: x - 26, y: 300, width: 52, height: 120), cornerWidth: 14, cornerHeight: 14)
    path.move(to: CGPoint(x: x - 86, y: 392))
    path.addLine(to: CGPoint(x: x + 86, y: 392))
    path.addLine(to: CGPoint(x: x, y: 470))
    path.closeSubpath()
    return path
}

func draw(in context: CGContext) {
    // Top-left origin, like the coordinates above.
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let outline = squircle(body)

    // Drop shadow of the whole tile, as on the macOS grid.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: color(0x000000, 0.30))
    context.addPath(outline)
    context.setFillColor(color(0x1B2F7A))
    context.fillPath()
    context.restoreGState()

    // Sky.
    context.saveGState()
    context.addPath(outline)
    context.clip()
    context.drawLinearGradient(gradient([color(0x5B9BFF), color(0x2E5BD8), color(0x1A2C78)], [0, 0.5, 1]),
                               start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.drawRadialGradient(gradient([color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)], [0, 1]),
                               startCenter: CGPoint(x: 512, y: 160), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 160), endRadius: 520, options: [])

    // Photo print, tilted, below the cloud.
    context.saveGState()
    context.translateBy(x: 512, y: 680)
    context.rotate(by: -5 * .pi / 180)
    let card = CGRect(x: -205, y: -150, width: 410, height: 300)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: color(0x0A1440, 0.45))
    context.addPath(CGPath(roundedRect: card, cornerWidth: 26, cornerHeight: 26, transform: nil))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    let picture = card.insetBy(dx: 22, dy: 22)
    context.saveGState()
    context.addPath(CGPath(roundedRect: picture, cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.clip()
    context.drawLinearGradient(gradient([color(0xFFD38A), color(0xFF8A5B), color(0xE0457B)], [0, 0.55, 1]),
                               start: CGPoint(x: 0, y: picture.minY), end: CGPoint(x: 0, y: picture.maxY), options: [])
    context.setFillColor(color(0xFFF4D6))
    context.fillEllipse(in: CGRect(x: 40, y: -88, width: 92, height: 92))
    let far = CGMutablePath()
    far.move(to: CGPoint(x: picture.minX, y: 60))
    far.addLine(to: CGPoint(x: -95, y: -40))
    far.addLine(to: CGPoint(x: -10, y: 30))
    far.addLine(to: CGPoint(x: 70, y: -20))
    far.addLine(to: CGPoint(x: picture.maxX, y: 70))
    far.addLine(to: CGPoint(x: picture.maxX, y: picture.maxY))
    far.addLine(to: CGPoint(x: picture.minX, y: picture.maxY))
    far.closeSubpath()
    context.addPath(far)
    context.setFillColor(color(0x7A2E6E))
    context.fillPath()
    let near = CGMutablePath()
    near.move(to: CGPoint(x: picture.minX, y: 95))
    near.addLine(to: CGPoint(x: -40, y: 40))
    near.addLine(to: CGPoint(x: 60, y: 100))
    near.addLine(to: CGPoint(x: 120, y: 62))
    near.addLine(to: CGPoint(x: picture.maxX, y: 110))
    near.addLine(to: CGPoint(x: picture.maxX, y: picture.maxY))
    near.addLine(to: CGPoint(x: picture.minX, y: picture.maxY))
    near.closeSubpath()
    context.addPath(near)
    context.setFillColor(color(0x3A1D5C))
    context.fillPath()
    context.restoreGState()
    context.restoreGState()

    // Cloud with the download arrow.
    let cloud = cloudPath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x0A1440, 0.40))
    context.addPath(cloud)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(cloud)
    context.clip()
    context.drawLinearGradient(gradient([color(0xFFFFFF), color(0xE4ECFF)], [0, 1]),
                               start: CGPoint(x: 512, y: 218), end: CGPoint(x: 512, y: 508), options: [])
    context.restoreGState()
    context.addPath(arrowPath())
    context.setFillColor(color(0x2E5BD8))
    context.fillPath()

    context.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}
try render(pixels: 1024).write(to: preview)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
