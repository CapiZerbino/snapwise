import AppKit

/// Watches window drags in other apps: dragging to a screen edge or corner, or onto a custom drop zone, snaps the window.
final class DragSnapMonitor {
    private enum Target: Equatable {
        case position(SnapPosition)
        case custom(CustomSnapArea)
    }

    private var monitors: [Any] = []
    private var candidate: AXWindow?
    private var startFrame: CGRect?
    /// Pre-snap size of the grabbed window, captured at mouse-down while it still sits at its snapped spot.
    private var restoreSize: CGSize?
    private var isWindowDrag = false
    private var dragEvents = 0
    private var target: Target?
    private var targetScreen: NSScreen?
    /// When the pointer reached an edge shared with another display; such edges need a short pause to count.
    private var sharedEdgeSince: Date?
    private var customAreas: [CustomSnapArea] = []
    private let preview = SnapPreview()
    private let zones = CustomZoneBar()
    private let prefs = Prefs.shared

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] _ in self?.mouseDragged() }),
            (.leftMouseUp, { [weak self] _ in self?.mouseUp() }),
            (.keyDown, { [weak self] event in if event.keyCode == 53 { self?.cancelDrag() } }),
        ]
        monitors = handlers.compactMap { NSEvent.addGlobalMonitorForEvents(matching: $0.0, handler: $0.1) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func reset() {
        candidate = nil
        startFrame = nil
        restoreSize = nil
        isWindowDrag = false
        dragEvents = 0
        target = nil
        targetScreen = nil
        sharedEdgeSince = nil
        preview.hide()
        zones.hide()
    }

    /// Esc during a drag: keep moving the window, but drop it wherever it is released.
    private func cancelDrag() {
        guard isWindowDrag else { return }
        candidate = nil
        target = nil
        preview.hide()
        zones.hide()
    }

    private func mouseDown() {
        reset()
        guard prefs.snapDrag, WindowAX.isTrusted, let window = WindowAX.window(at: WindowAX.pointerLocation),
              window.pid != getpid(), !SnapManager.shared.isExcluded(window) else { return }
        candidate = window
        startFrame = window.frame
        restoreSize = prefs.snapRestoreOnDrag ? SnapManager.shared.originalSize(ofSnapped: window) : nil
    }

    private func mouseDragged() {
        guard let window = candidate, let start = startFrame else { return }
        dragEvents += 1
        if !isWindowDrag {
            // Asking the window for its frame is an IPC round trip; sample instead of checking every event.
            guard dragEvents % 4 == 0, let now = window.frame else { return }
            if abs(now.width - start.width) > 1 || abs(now.height - start.height) > 1 { return reset() } // a resize, not a move
            guard now.origin.distance(to: start.origin) > 6 else { return }
            isWindowDrag = true
            customAreas = CustomSnapArea.load()
            if let size = restoreSize {
                // Shrink back to the pre-snap size and keep the grabbed spot under the pointer.
                let pointer = WindowAX.pointerLocation
                let grab = max(0.05, min(0.95, (pointer.x - now.minX) / max(now.width, 1)))
                window.setSize(size)
                window.setPosition(CGPoint(x: pointer.x - size.width * grab, y: now.minY))
                SnapManager.shared.forget(window)
            }
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(pointer) }) else { return }
        zones.show(areas: customAreas, on: screen)

        var next: Target?
        if let area = zones.area(at: pointer) {
            next = .custom(area)
        } else if let position = edgePosition(pointer: pointer, screen: screen) {
            next = .position(position)
        }
        zones.highlight(next.flatMap { if case .custom(let area) = $0 { return area.id } else { return nil } })
        guard next != target || screen != targetScreen else { return }
        target = next
        targetScreen = screen
        if next != nil, prefs.snapHaptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        let usable = Geo.flipGlobal(screen.visibleFrame)
        let gap = CGFloat(prefs.snapGap)
        switch next {
        case .position(let position): preview.show(position.frame(in: usable, gap: gap))
        case .custom(let area): preview.show(SnapGeometry.frame(fractions: area.fractions, in: usable, gap: gap))
        case nil: preview.hide()
        }
    }

    /// Edge snapping, with a dwell requirement on edges that border another display so crossing over does not trigger it.
    private func edgePosition(pointer: CGPoint, screen: NSScreen) -> SnapPosition? {
        guard let position = SnapGeometry.position(forPointer: pointer, in: screen.frame, threshold: 6) else {
            // Shared edges are detected in a wider band because the pointer does not stop there.
            guard let wide = SnapGeometry.position(forPointer: pointer, in: screen.frame, threshold: 28), isShared(wide, on: screen) else {
                sharedEdgeSince = nil
                return nil
            }
            let since = sharedEdgeSince ?? Date()
            sharedEdgeSince = since
            return Date().timeIntervalSince(since) > 0.35 ? wide : nil
        }
        if isShared(position, on: screen) {
            let since = sharedEdgeSince ?? Date()
            sharedEdgeSince = since
            return Date().timeIntervalSince(since) > 0.35 ? position : nil
        }
        sharedEdgeSince = nil
        return position
    }

    private func isShared(_ position: SnapPosition, on screen: NSScreen) -> Bool {
        let y = screen.frame.midY
        let probe: CGPoint
        switch position {
        case .leftHalf, .topLeft, .bottomLeft: probe = CGPoint(x: screen.frame.minX - 10, y: y)
        case .rightHalf, .topRight, .bottomRight: probe = CGPoint(x: screen.frame.maxX + 10, y: y)
        case .maximize: probe = CGPoint(x: screen.frame.midX, y: screen.frame.maxY + 10)
        default: return false
        }
        return NSScreen.screens.contains { $0 != screen && $0.frame.contains(probe) }
    }

    private func mouseUp() {
        defer { reset() }
        guard isWindowDrag, let window = candidate, let target, let screen = targetScreen else { return }
        // Give the app a moment to finish its own drag before repositioning the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            switch target {
            case .custom(let area):
                SnapManager.shared.snap(to: area, on: screen, window: window)
            case .position(let position):
                let usable = Geo.flipGlobal(screen.visibleFrame)
                if let rect = position.frame(in: usable, gap: CGFloat(Prefs.shared.snapGap)) { SnapManager.shared.apply(rect, to: window) }
            }
        }
    }
}

/// Frosted outline showing where a window will land (while dragging) or just landed (keyboard snaps).
final class SnapPreview {
    private var panel: OverlayPanel?
    private var generation = 0

    /// `rect` is in CoreGraphics global coordinates.
    func show(_ rect: CGRect?) {
        guard let rect else { return hide() }
        generation += 1
        let frame = Geo.flipGlobal(rect).insetBy(dx: 5, dy: 5)
        if panel == nil {
            let panel = OverlayPanel(frame: frame, level: .floating, clickThrough: true)
            panel.allowsKey = false
            let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
            glass.material = .fullScreenUI
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.autoresizingMask = [.width, .height]
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 14
            glass.layer?.masksToBounds = true
            // Light frosting: the content underneath should stay recognisable.
            glass.alphaValue = 0.62
            glass.layer?.borderWidth = 2.5
            glass.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            let tint = NSView(frame: glass.bounds)
            tint.autoresizingMask = [.width, .height]
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            glass.addSubview(tint)
            panel.contentView = glass
            panel.alphaValue = 0
            // Grow out of the middle of the target so the eye is led to where the window will go.
            panel.setFrame(frame.insetBy(dx: frame.width * 0.08, dy: frame.height * 0.08), display: false)
            panel.orderFrontRegardless()
            self.panel = panel
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().setFrame(frame, display: true)
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        generation += 1
        guard let closing = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            closing.animator().alphaValue = 0
        }, completionHandler: { closing.close() })
    }

    /// Briefly outlines `rect` to confirm a snap that was not preceded by a drag preview.
    func flash(_ rect: CGRect) {
        show(rect)
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            if self?.generation == shown { self?.hide() }
        }
    }
}

/// Row of labelled drop zones for the user's custom snap areas, shown at the top of the screen during a window drag.
final class CustomZoneBar {
    private var panel: OverlayPanel?
    private var view: ZoneBarView?
    private var screen: NSScreen?

    func show(areas: [CustomSnapArea], on screen: NSScreen) {
        guard !areas.isEmpty else { return }
        if panel != nil, self.screen == screen { return }
        hide()
        let chip = CGSize(width: 132, height: 76), spacing: CGFloat = 10
        let size = CGSize(width: CGFloat(areas.count) * (chip.width + spacing) + spacing, height: chip.height + spacing * 2)
        let visible = screen.visibleFrame
        let panel = OverlayPanel(frame: CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40, width: size.width, height: size.height),
                                 level: .floating, clickThrough: true)
        panel.allowsKey = false
        let view = ZoneBarView(areas: areas, chip: chip, spacing: spacing, frame: CGRect(origin: .zero, size: size))
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        self.view = view
        self.screen = screen
    }

    func hide() {
        panel?.close()
        panel = nil
        view = nil
        screen = nil
    }

    /// The zone under a pointer position in AppKit global coordinates.
    func area(at pointer: CGPoint) -> CustomSnapArea? {
        guard let panel, let view else { return nil }
        return view.area(at: CGPoint(x: pointer.x - panel.frame.minX, y: pointer.y - panel.frame.minY))
    }

    func highlight(_ id: UUID?) {
        guard let view, view.highlighted != id else { return }
        view.highlighted = id
        view.needsDisplay = true
    }
}

private final class ZoneBarView: NSView {
    let areas: [CustomSnapArea]
    let chip: CGSize
    let spacing: CGFloat
    var highlighted: UUID?

    init(areas: [CustomSnapArea], chip: CGSize, spacing: CGFloat, frame: CGRect) {
        self.areas = areas
        self.chip = chip
        self.spacing = spacing
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func rect(_ index: Int) -> CGRect {
        CGRect(x: spacing + CGFloat(index) * (chip.width + spacing), y: spacing, width: chip.width, height: chip.height)
    }

    func area(at point: CGPoint) -> CustomSnapArea? {
        areas.indices.first { rect($0).contains(point) }.map { areas[$0] }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
        for (index, area) in areas.enumerated() {
            let r = rect(index)
            let active = area.id == highlighted
            (active ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.14)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            // Miniature of where the window will go.
            let mini = CGRect(x: r.minX + 10, y: r.minY + 26, width: r.width - 20, height: r.height - 36)
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: mini, xRadius: 3, yRadius: 3).fill()
            let f = area.fractions
            NSColor.white.setFill()
            NSBezierPath(roundedRect: CGRect(x: mini.minX + mini.width * f.minX, y: mini.maxY - mini.height * f.maxY,
                                             width: mini.width * f.width, height: mini.height * f.height), xRadius: 2, yRadius: 2).fill()
            let title = NSAttributedString(string: area.name, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            let size = title.size()
            title.draw(at: CGPoint(x: r.midX - min(size.width, r.width - 8) / 2, y: r.minY + 7))
        }
    }
}
