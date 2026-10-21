// Draws the Docket app icon from the SF Symbol the menu bar uses (`docs/05-design.md` §4).
// Usage: swift scripts/generate-icons.swift App/Resources/Assets.xcassets
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let set = output.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // The macOS icon grid: an 824-unit rounded square inside a 1024 canvas.
    let inset = size * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(
        starting: NSColor(srgbRed: 0.33, green: 0.45, blue: 0.98, alpha: 1),
        ending: NSColor(srgbRed: 0.18, green: 0.24, blue: 0.72, alpha: 1)
    )?.draw(in: shape, angle: -90)
    let configuration = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    {
        let bounds = symbol.size
        let origin = NSPoint(x: tile.midX - bounds.width / 2, y: tile.midY - bounds.height / 2)
        symbol.draw(in: NSRect(origin: origin, size: bounds))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale)?.write(to: set.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appending(path: "Contents.json"))
