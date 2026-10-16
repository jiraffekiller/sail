// Generates Resources/AppIcon.icns: a white sailboat on a sea gradient inside the
// macOS squircle. Run: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    // macOS icon shape: rounded rect with ~22.4 % corner radius, slightly inset.
    let inset = size * 0.04
    let shape = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                             xRadius: size * 0.224, yRadius: size * 0.224)
    shape.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.36, blue: 0.78, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.60, blue: 0.86, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: 90)
    // Subtle highlight at the top.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.16)])!
        .draw(in: rect, angle: 90)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "sailboat.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        symbol.draw(at: .zero, from: NSRect(origin: .zero, size: symbol.size), operation: .sourceOver, fraction: 1)
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let s = tinted.size
        let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2 - size * 0.02)
        // Soft shadow.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = size * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
        shadow.set()
        tinted.draw(at: origin, from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1)
    }
    img.unlockFocus()
    return img
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let master = render(size: 1024)
for base in [16, 32, 128, 256, 512] {
    try! png(master, pixels: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(master, pixels: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("wrote \(out.path)")
