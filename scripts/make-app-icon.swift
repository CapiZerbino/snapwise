// Renders the app icon at every size macOS asks for. Usage: swift scripts/make-app-icon.swift <appiconset dir>
//
// The mark shows both halves of the app: a window snapped to the left half of a screen,
// and a capture viewfinder with a shutter dot on the right half.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var images: [[String: String]] = []

func draw(side s: CGFloat) {
    // macOS icon grid: the body fills ~80 % of the canvas, leaving room for the drop shadow.
    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let radius = body.width * 0.225
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.56, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.42, green: 0.30, blue: 0.93, alpha: 1)])!
        .draw(in: shape, angle: -60)
    // Soft top highlight for depth.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Content area: two tiles separated by a gap, like two snapped windows.
    let inset = body.width * 0.17
    let area = body.insetBy(dx: inset, dy: inset * 1.12)
    let gap = body.width * 0.055
    let tileWidth = (area.width - gap) / 2
    let tileRadius = body.width * 0.06

    // Left tile: the snapped window, solid, with a title bar hint.
    let left = NSRect(x: area.minX, y: area.minY, width: tileWidth, height: area.height)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: left, xRadius: tileRadius, yRadius: tileRadius).fill()
    if s >= 64 {
        NSColor(srgbRed: 0.40, green: 0.38, blue: 0.95, alpha: 0.9).setFill()
        let dot = left.width * 0.11
        for i in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: left.minX + left.width * 0.14 + CGFloat(i) * dot * 1.55, y: left.maxY - left.width * 0.14 - dot,
                                        width: dot, height: dot)).fill()
        }
    }

    // Right tile: capture viewfinder — corner brackets around a shutter dot.
    let right = NSRect(x: area.minX + tileWidth + gap, y: area.minY, width: tileWidth, height: area.height)
    let stroke = max(1, body.width * 0.05)
    let arm = right.width * 0.27
    let frame = right.insetBy(dx: stroke / 2, dy: stroke / 2)
    let brackets = NSBezierPath()
    brackets.lineWidth = stroke
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    for (cx, cy, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                             (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
        brackets.move(to: NSPoint(x: cx + arm * dx, y: cy))
        brackets.line(to: NSPoint(x: cx, y: cy))
        brackets.line(to: NSPoint(x: cx, y: cy + arm * dy))
    }
    NSColor.white.setStroke()
    brackets.stroke()
    let shutter = right.width * 0.3
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: right.midX - shutter / 2, y: right.midY - shutter / 2, width: shutter, height: shutter)).fill()
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(side: CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
