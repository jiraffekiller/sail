// Renders the DMG window background (Retina, 144 dpi): a hint arrow between the app
// icon slot (left) and the Applications slot (right). Window is 660x400 points.
//   swift scripts/make-dmg-background.swift Resources/dmg-background.png
import AppKit
let W: CGFloat = 660, H: CGFloat = 400, scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)   // 144 dpi
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.17, alpha: 1),
                    NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.32, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 62)
// arrow between the two icon slots (icons sit at y≈190 from top → 210 from bottom)
let path = NSBezierPath()
path.move(to: NSPoint(x: 262, y: 210)); path.line(to: NSPoint(x: 398, y: 210))
path.move(to: NSPoint(x: 372, y: 236)); path.line(to: NSPoint(x: 398, y: 210)); path.line(to: NSPoint(x: 372, y: 184))
path.lineWidth = 8; path.lineCapStyle = .round; path.lineJoinStyle = .round
NSColor.white.withAlphaComponent(0.85).setStroke(); path.stroke()
let p = NSMutableParagraphStyle(); p.alignment = .center
let title = NSAttributedString(string: "Drag Sail to Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: p])
title.draw(in: NSRect(x: 0, y: 320, width: W, height: 34))
let sub = NSAttributedString(string: "Then open it once from Applications. macOS will ask you to allow it under\nSystem Settings → Privacy & Security → Open Anyway (the app is not notarized).", attributes: [
    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.65), .paragraphStyle: p])
sub.draw(in: NSRect(x: 30, y: 36, width: W - 60, height: 40))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
