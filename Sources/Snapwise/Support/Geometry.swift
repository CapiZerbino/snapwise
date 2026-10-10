import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// Height of the primary display; the pivot between AppKit (bottom-left) and CoreGraphics (top-left) global space.
    static var primaryHeight: CGFloat { screens.first?.frame.height ?? 0 }

    static var underMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(p) } ?? main ?? screens[0]
    }

    static func with(displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    /// Converts an AppKit global rect to this display's local space with a top-left origin (ScreenCaptureKit `sourceRect`).
    func localTopLeft(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - frame.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
    }
}

enum Geo {
    /// Flips a global rect between AppKit and CoreGraphics coordinate spaces (the operation is its own inverse).
    static func flipGlobal(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: NSScreen.primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func aspectFit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let s = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * s, height: size.height * s)
    }
}

extension CGRect {
    init(from a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func scaled(by s: CGFloat) -> CGRect {
        CGRect(x: minX * s, y: minY * s, width: width * s, height: height * s)
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }

    var length: CGFloat { hypot(x, y) }

    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }

    /// Shortest distance from this point to the segment `a`–`b`.
    func distance(toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = b - a
        let len2 = ab.x * ab.x + ab.y * ab.y
        guard len2 > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * ab.x + (y - a.y) * ab.y) / len2))
        return distance(to: CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t))
    }
}
