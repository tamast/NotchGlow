import Cocoa

// Renders the NotchGlow app icon at 1024x1024 to the path given as argv[1].
// Design: dark rounded square, notch shape at top with green border — reads as
// "glowing frame around the notch".

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: render-icon <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = CommandLine.arguments[1]

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon metrics: artwork lives in an inner rounded square (~80% of canvas).
let iconRect = NSRect(x: 102, y: 102, width: 820, height: 820)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 190, yRadius: 190)

// Background: dark blue-grey vertical gradient
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.10, alpha: 1),
])!
gradient.draw(in: iconPath, angle: -90)

// Notch shape: bar hanging from top-center edge of the icon
let notchW: CGFloat = 250
let notchH: CGFloat = 150
let notchX = (size - notchW) / 2
let notchY = iconRect.maxY - notchH + 30   // dips into the top edge
let notchRect = NSRect(x: notchX, y: notchY, width: notchW, height: notchH)
let notchRadius: CGFloat = 48

// Rounded bottom corners only: build path manually
let n = NSBezierPath()
let nr = notchRect
n.move(to: NSPoint(x: nr.minX, y: nr.maxY + 40))                    // top-left (above clip)
n.line(to: NSPoint(x: nr.minX, y: nr.minY + notchRadius))
n.appendArc(
    withCenter: NSPoint(x: nr.minX + notchRadius, y: nr.minY + notchRadius),
    radius: notchRadius, startAngle: 180, endAngle: 270)
n.line(to: NSPoint(x: nr.maxX - notchRadius, y: nr.minY))
n.appendArc(
    withCenter: NSPoint(x: nr.maxX - notchRadius, y: nr.minY + notchRadius),
    radius: notchRadius, startAngle: 270, endAngle: 0)
n.line(to: NSPoint(x: nr.maxX, y: nr.maxY + 40))
n.close()

// Green border stroke around notch (the "glow frame")
let green = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
NSGraphicsContext.saveGraphicsState()
iconPath.addClip()
// Notch fill: near-black (inside clip so it doesn't spill above the icon)
NSColor(calibratedRed: 0.01, green: 0.01, blue: 0.02, alpha: 1).setFill()
n.fill()
let glow = NSShadow()
glow.shadowColor = green.withAlphaComponent(0.8)
glow.shadowBlurRadius = 28
glow.shadowOffset = .zero
glow.set()
// soft glow pass
green.withAlphaComponent(0.5).setStroke()
n.lineWidth = 30
n.stroke()
// main border
green.setStroke()
n.lineWidth = 18
n.stroke()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("render-icon: PNG encode failed\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
} catch {
    FileHandle.standardError.write("render-icon: \(error)\n".data(using: .utf8)!)
    exit(1)
}
