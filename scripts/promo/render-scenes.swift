// Renders the still frames for the promo video. Usage:
//   swift scripts/promo/render-scenes.swift <icon.png> <menu.png> <setup.png> <outdir>
import AppKit

let args = CommandLine.arguments
let iconPath = args[1], menuPath = args[2], setupPath = args[3]
let outDir = URL(fileURLWithPath: args[4])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let W: CGFloat = 1920, H: CGFloat = 1080
let bgTop = NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.22, alpha: 1)
let bgBottom = NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.12, alpha: 1)
let accent = NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1)
let fg = NSColor.white
let dim = NSColor(white: 1, alpha: 0.62)

func load(_ p: String) -> NSImage { NSImage(contentsOfFile: p)! }
let icon = load(iconPath), menu = load(menuPath), setup = load(setupPath)

func paragraph(_ align: NSTextAlignment, spacing: CGFloat = 6) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineSpacing = spacing; return p
}
func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = fg,
          align: NSTextAlignment = .left, mono: Bool = false) -> NSAttributedString {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph(align)])
}
func draw(_ a: NSAttributedString, in r: NSRect) { a.draw(with: r, options: [.usesLineFragmentOrigin]) }

/// Draws an image fitted into `rect` with rounded corners and a soft shadow.
func drawShot(_ img: NSImage, in rect: NSRect, radius: CGFloat = 22) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -18); shadow.set()
    NSColor.black.withAlphaComponent(0.3).set()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}
func fit(_ img: NSImage, height: CGFloat) -> NSSize { NSSize(width: img.size.width / img.size.height * height, height: height) }

func scene(_ name: String, _ body: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(colors: [bgBottom, bgTop, bgTop.blended(withFraction: 0.35, of: accent)!])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 62)
    body()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("rendered \(name)")
}

// 1. Title
scene("01-title.png") {
    icon.draw(in: NSRect(x: 560, y: 440, width: 260, height: 260), from: .zero, operation: .sourceOver, fraction: 1)
    draw(text("Sail", size: 150, weight: .bold), in: NSRect(x: 870, y: 470, width: 800, height: 200))
    draw(text("Battery charge limiter for Apple Silicon MacBooks", size: 42, color: dim), in: NSRect(x: 874, y: 400, width: 900, height: 70))
}

// 2. Problem
scene("02-problem.png") {
    draw(text("macOS 26.4 can limit charging.", size: 78, weight: .semibold), in: NSRect(x: 180, y: 600, width: 1600, height: 110))
    draw(text("System Settings stops at 80 %.", size: 78, weight: .semibold, color: dim), in: NSRect(x: 180, y: 490, width: 1600, height: 110))
    draw(text("Sail takes the same mechanism all the way down to 1 % —\nand sails between two bounds instead of topping up every time you plug in.", size: 40, color: fg), in: NSRect(x: 184, y: 300, width: 1560, height: 140))
}

// 3. Sailing mode
let menuSize = fit(menu, height: 880)
let menuRect = NSRect(x: W - menuSize.width - 170, y: (H - menuSize.height) / 2, width: menuSize.width, height: menuSize.height)
scene("03-sailing.png") {
    drawShot(menu, in: menuRect)
    draw(text("Sailing mode", size: 84, weight: .bold), in: NSRect(x: 180, y: 640, width: 900, height: 120))
    draw(text("Charge to 70 %.\nHold — no top-ups while plugged in.\nRecharge only below 60 %.", size: 44, color: fg), in: NSRect(x: 184, y: 380, width: 820, height: 240))
    draw(text("Both bounds are sliders in the menu.", size: 34, color: dim), in: NSRect(x: 184, y: 300, width: 820, height: 60))
}

// 4. Heat protection
scene("04-heat.png") {
    drawShot(menu, in: menuRect)
    draw(text("Heat protection", size: 84, weight: .bold), in: NSRect(x: 180, y: 640, width: 900, height: 120))
    draw(text("Pauses charging above 35 °C.\nResumes a few degrees lower.", size: 44, color: fg), in: NSRect(x: 184, y: 450, width: 820, height: 160))
    draw(text("Battery temperature straight from the SMC sensors.", size: 34, color: dim), in: NSRect(x: 184, y: 370, width: 820, height: 60))
}

// 5. Setup
let setupSize = fit(setup, height: 920)
scene("05-setup.png") {
    drawShot(setup, in: NSRect(x: W - setupSize.width - 190, y: (H - setupSize.height) / 2, width: setupSize.width, height: setupSize.height))
    draw(text("Set up in a minute", size: 84, weight: .bold), in: NSRect(x: 180, y: 640, width: 1000, height: 120))
    draw(text("Compatibility checks.\nOne-time helper install (admin password).\nSelf-test: macOS confirms the limit.", size: 44, color: fg), in: NSRect(x: 184, y: 380, width: 900, height: 240))
}

// 6. Enforced by macOS
scene("06-enforced.png") {
    draw(text("Enforced by macOS itself", size: 84, weight: .bold), in: NSRect(x: 180, y: 640, width: 1600, height: 120))
    draw(text("The limit lives in powerd, not in the app.\nIt survives sleep, a closed lid, and Sail not running.", size: 46, color: fg), in: NSRect(x: 184, y: 430, width: 1560, height: 170))
    draw(text("Menu bar only. Starts at login. Restarted by launchd if it ever crashes.", size: 34, color: dim), in: NSRect(x: 184, y: 340, width: 1560, height: 60))
}

// 7. Install
scene("07-install.png") {
    icon.draw(in: NSRect(x: 180, y: 620, width: 180, height: 180), from: .zero, operation: .sourceOver, fraction: 1)
    draw(text("Free and open source · GPL-3.0", size: 44, weight: .semibold), in: NSRect(x: 400, y: 690, width: 1300, height: 70))
    draw(text("Apple Silicon · macOS 26.4 or newer", size: 36, color: dim), in: NSRect(x: 404, y: 630, width: 1300, height: 60))
    NSColor.white.withAlphaComponent(0.08).set()
    NSBezierPath(roundedRect: NSRect(x: 180, y: 420, width: 1560, height: 120), xRadius: 18, yRadius: 18).fill()
    draw(text("brew install --cask jiraffekiller/tap/sail-battery", size: 40, weight: .medium, color: fg, mono: true), in: NSRect(x: 220, y: 455, width: 1500, height: 60))
    draw(text("github.com/jiraffekiller/sail", size: 44, weight: .medium, color: accent), in: NSRect(x: 184, y: 320, width: 1200, height: 70))
}
