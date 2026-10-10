import AppKit

enum SelectionMode {
    case area, window, allInOne, record
}

/// Full-screen view that lets the user drag out an area or pick a window. One instance per display.
final class SelectionView: NSView {
    var mode: SelectionMode
    let screen: NSScreen
    /// Display contents at overlay start; feeds the magnifier and, when `frozen`, the backdrop.
    let snapshot: CGImage?
    let frozen: Bool
    let windows: [WindowInfo]
    var hint = ""
    /// All-In-One and recording keep the selection on screen for adjustment until an action is chosen.
    var staysAdjustable: Bool { mode == .allInOne || mode == .record }
    var lockedAspect: CGFloat?

    /// View-local selection rect.
    private(set) var selection: CGRect?
    private(set) var adjusting = false
    private var hoveredWindow: WindowInfo?
    private var mouse = CGPoint.zero
    private var mouseInside = false
    private var drag: Drag?

    var onArea: ((CGRect) -> Void)?
    var onWindow: ((WindowInfo) -> Void)?
    var onFullscreen: (() -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onSelectionChanged: ((CGRect?) -> Void)?
    var onToggleMode: (() -> Void)?

    private enum Drag {
        case new(start: CGPoint)
        case move(grab: CGPoint, original: CGRect)
        case resize(dx: Int, dy: Int, original: CGRect)
    }

    private let handleSize: CGFloat = 9

    init(screen: NSScreen, mode: SelectionMode, snapshot: CGImage?, frozen: Bool, windows: [WindowInfo]) {
        self.screen = screen
        self.mode = mode
        self.snapshot = snapshot
        self.frozen = frozen && snapshot != nil
        self.windows = windows
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    var globalSelection: CGRect? { selection.map { $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY) } }

    func setSelection(_ rect: CGRect?, adjusting: Bool) {
        selection = rect.map { clamp($0) }
        self.adjusting = adjusting && rect != nil
        needsDisplay = true
        onSelectionChanged?(selection)
    }

    func clearSelection() {
        selection = nil
        adjusting = false
        drag = nil
        needsDisplay = true
    }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        hoveredWindow = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseInside = true
        mouse = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        if mode == .window {
            let global = mouse + screen.frame.origin
            hoveredWindow = windows.first { $0.frame.contains(global) }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        if mode == .window {
            if let hoveredWindow { onWindow?(hoveredWindow) }
            return
        }
        if adjusting, let sel = selection {
            if let (dx, dy) = handle(at: p, in: sel) {
                drag = .resize(dx: dx, dy: dy, original: sel)
                return
            }
            if sel.contains(p) {
                drag = .move(grab: p, original: sel)
                return
            }
        }
        adjusting = false
        selection = nil
        drag = .new(start: p)
        needsDisplay = true
    }

    /// Works even when the panel lost key focus and Esc no longer reaches it.
    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        guard let drag else { return }
        switch drag {
        case .new(let start):
            var end = p
            let aspect = lockedAspect ?? (event.modifierFlags.contains(.shift) ? 1 : nil)
            if let aspect {
                let w = abs(p.x - start.x), h = w / aspect
                end = CGPoint(x: p.x, y: start.y + (p.y < start.y ? -h : h))
            }
            selection = clamp(CGRect(from: start, to: end))
        case .move(let grab, let original):
            var r = original.offsetBy(dx: p.x - grab.x, dy: p.y - grab.y)
            r.origin.x = max(0, min(bounds.width - r.width, r.minX))
            r.origin.y = max(0, min(bounds.height - r.height, r.minY))
            selection = r
        case .resize(let dx, let dy, let original):
            var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
            if dx < 0 { minX = min(p.x, maxX - 8) } else if dx > 0 { maxX = max(p.x, minX + 8) }
            if dy < 0 { minY = min(p.y, maxY - 8) } else if dy > 0 { maxY = max(p.y, minY + 8) }
            var r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            if let aspect = lockedAspect {
                // Keep the top edge fixed so the selection grows downward, as when dragging.
                let h = r.width / aspect
                r = CGRect(x: r.minX, y: r.maxY - h, width: r.width, height: h)
            }
            selection = clamp(r)
        }
        needsDisplay = true
        onSelectionChanged?(selection)
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        guard drag != nil, let sel = selection, sel.width >= 4, sel.height >= 4 else {
            if case .new = drag {
                selection = nil
                needsDisplay = true
                onSelectionChanged?(nil)
            }
            return
        }
        let rounded = sel.integral
        selection = rounded
        if staysAdjustable {
            adjusting = true
            needsDisplay = true
            onSelectionChanged?(rounded)
        } else if case .new = drag {
            onArea?(rounded.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY))
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?() // esc
        case 49: onToggleMode?() // space
        case 36, 76: // return / enter
            if adjusting { onConfirm?() } else { onFullscreen?() }
        case 3 where mode != .allInOne || !adjusting: onFullscreen?() // F
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if frozen, let snapshot { ctx.draw(snapshot, in: bounds) }

        let hoverRect = hoveredWindow.map { $0.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }
        let hole = selection ?? (mode == .window ? hoverRect : nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(hole == nil ? 0.18 : 0.4).cgColor)
        ctx.addRect(bounds)
        if let hole { ctx.addRect(hole) }
        ctx.fillPath(using: .evenOdd)

        if mode == .window, let hoverRect {
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor)
            ctx.fill(hoverRect)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(hoverRect.insetBy(dx: 1, dy: 1))
        }

        if let sel = selection {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(sel.insetBy(dx: -1, dy: -1))
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))
            drawSizeLabel(for: sel)
            if adjusting { handleRects(for: sel).forEach { drawHandle($0.rect, in: ctx) } }
        }

        let showAids = mouseInside && mode != .window && !adjusting
        if showAids, selection == nil, Prefs.shared.showCrosshair {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            ctx.fill(CGRect(x: 0, y: mouse.y - 0.5, width: bounds.width, height: 1))
            ctx.fill(CGRect(x: mouse.x - 0.5, y: 0, width: 1, height: bounds.height))
        }
        if showAids, Prefs.shared.showMagnifier { drawMagnifier(in: ctx) }
        if selection == nil, !hint.isEmpty, mouseInside { drawHint() }
    }

    private func drawHandle(_ rect: CGRect, in ctx: CGContext) {
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: rect)
    }

    private func pill(_ text: String, font: NSFont) -> (NSAttributedString, CGSize) {
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = str.size()
        return (str, CGSize(width: ceil(size.width) + 14, height: ceil(size.height) + 6))
    }

    private func drawPill(_ str: NSAttributedString, size: CGSize, at origin: CGPoint) {
        let rect = CGRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        str.draw(at: CGPoint(x: rect.minX + 7, y: rect.minY + 3))
    }

    private func drawSizeLabel(for sel: CGRect) {
        let (str, size) = pill("\(Int(sel.width)) × \(Int(sel.height))", font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        var origin = CGPoint(x: sel.maxX - size.width, y: sel.minY - size.height - 6)
        if origin.y < 4 { origin.y = sel.minY + 6 }
        origin.x = max(4, origin.x)
        drawPill(str, size: size, at: origin)
    }

    private func drawHint() {
        let (str, size) = pill(hint, font: .systemFont(ofSize: 12, weight: .medium))
        drawPill(str, size: size, at: CGPoint(x: bounds.midX - size.width / 2, y: 72))
    }

    private func drawMagnifier(in ctx: CGContext) {
        guard let snapshot else { return }
        let diameter: CGFloat = 116, zoom: CGFloat = 8
        let scale = CGFloat(snapshot.width) / bounds.width
        var origin = CGPoint(x: mouse.x + 18, y: mouse.y - diameter - 18)
        if origin.x + diameter > bounds.width - 4 { origin.x = mouse.x - diameter - 18 }
        if origin.y < 28 { origin.y = mouse.y + 18 }
        let circle = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))

        let side = diameter / zoom // source side in points
        let source = CGRect(x: (mouse.x - side / 2) * scale, y: (bounds.height - mouse.y - side / 2) * scale,
                            width: side * scale, height: side * scale)
        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(circle)
        if let crop = snapshot.cropping(to: source) {
            ctx.interpolationQuality = .none
            // Near screen edges the crop is clipped; place it so each source pixel keeps its position.
            let k = diameter / source.width
            let drawn = CGRect(x: circle.minX + (CGFloat(crop.width) < source.width && source.minX < 0 ? -source.minX * k : 0),
                               y: circle.minY + (CGFloat(crop.height) < source.height && source.minY >= 0 ? (source.height - CGFloat(crop.height)) * k : 0),
                               width: CGFloat(crop.width) * k, height: CGFloat(crop.height) * k)
            ctx.draw(crop, in: drawn)
        }
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        ctx.fill(CGRect(x: circle.midX - 0.5, y: circle.minY, width: 1, height: diameter))
        ctx.fill(CGRect(x: circle.minX, y: circle.midY - 0.5, width: diameter, height: 1))
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: circle)

        let (str, size) = pill("\(Int(mouse.x)), \(Int(bounds.height - mouse.y))", font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium))
        drawPill(str, size: size, at: CGPoint(x: circle.midX - size.width / 2, y: circle.minY - size.height - 4))
    }

    // MARK: - Helpers

    private func clamp(_ r: CGRect) -> CGRect { r.intersection(bounds) }

    private func handleRects(for sel: CGRect) -> [(dx: Int, dy: Int, rect: CGRect)] {
        var result: [(Int, Int, CGRect)] = []
        for dx in -1...1 {
            for dy in -1...1 where !(dx == 0 && dy == 0) {
                let x = dx < 0 ? sel.minX : (dx > 0 ? sel.maxX : sel.midX)
                let y = dy < 0 ? sel.minY : (dy > 0 ? sel.maxY : sel.midY)
                result.append((dx, dy, CGRect(x: x - handleSize / 2, y: y - handleSize / 2, width: handleSize, height: handleSize)))
            }
        }
        return result
    }

    private func handle(at p: CGPoint, in sel: CGRect) -> (Int, Int)? {
        handleRects(for: sel).first { $0.rect.insetBy(dx: -5, dy: -5).contains(p) }.map { ($0.dx, $0.dy) }
    }
}
