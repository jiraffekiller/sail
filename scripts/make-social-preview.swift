// Renders docs/social.png (1280x640): the repository's social preview / article og:image.
//   swift scripts/make-social-preview.swift build/AppIcon.iconset/icon_512x512@2x.png docs/social.png
import AppKit
let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let W: CGFloat = 1280, H: CGFloat = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bg = NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.12, alpha: 1), mid = NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.24, alpha: 1), hi = NSColor(calibratedRed: 0.09, green: 0.23, blue: 0.40, alpha: 1)
NSGradient(colors: [bg, mid, hi])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 62)
// waves
let wave = NSBezierPath(); wave.move(to: NSPoint(x: 0, y: 70))
for x in stride(from: 0, through: Int(W), by: 10) { let fx = CGFloat(x); wave.line(to: NSPoint(x: fx, y: 70 + 18 * sin(fx / 90))) }
wave.line(to: NSPoint(x: W, y: 0)); wave.line(to: NSPoint(x: 0, y: 0)); wave.close()
NSColor(calibratedRed: 0.31, green: 0.70, blue: 1, alpha: 0.18).setFill(); wave.fill()
icon.draw(in: NSRect(x: 96, y: 236, width: 200, height: 200), from: .zero, operation: .sourceOver, fraction: 1)
func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, _ r: NSRect) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(with: r, options: [.usesLineFragmentOrigin])
}
text("Sail", 110, .bold, .white, NSRect(x: 340, y: 330, width: 900, height: 130))
text("Battery charge limiter for Apple Silicon MacBooks", 34, .regular, NSColor(white: 1, alpha: 0.75), NSRect(x: 346, y: 282, width: 900, height: 44))
text("Sailing mode · Heat protection · Any limit, 1–100 %", 30, .medium, NSColor(calibratedRed: 0.31, green: 0.70, blue: 1, alpha: 1), NSRect(x: 346, y: 226, width: 900, height: 40))
text("Free · Open source · macOS 26.4+", 24, .regular, NSColor(white: 1, alpha: 0.55), NSRect(x: 348, y: 180, width: 900, height: 34))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("wrote \(CommandLine.arguments[2])")
