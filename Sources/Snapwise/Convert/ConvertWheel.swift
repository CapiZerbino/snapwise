import AppKit

/// The radial menu. In drag mode it appears under the pointer while a file is dragged and takes the drop;
/// in click mode (Convert Files…) the chosen files are already known and bubbles are clicked or picked with the keyboard.
final class ConvertWheel {
    static let shared = ConvertWheel()

    enum Mode { case drag, click }

    private var panel: OverlayPanel?
    private var wheel: WheelView?
    private var watchdog: Timer?
    private var mode: Mode = .drag
    private var buttonReleasedAt: Date?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel != nil }

    func show(_ kind: WheelKind, files: [URL], at point: CGPoint, mode: Mode) {
        hide(animated: false)
        self.mode = mode
        let size = WheelView.size
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? .underMouse
        let area = screen.visibleFrame
        // Centred on the pointer so the file is over the hub, then nudged on screen.
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y - WheelView.hub.y)
        origin.x = min(max(origin.x, area.minX + 4), area.maxX - size.width - 4)
        origin.y = min(max(origin.y, area.minY + 4), area.maxY - size.height - 4)

        let panel = OverlayPanel(frame: CGRect(origin: origin, size: size), level: .popUpMenu)
        panel.allowsKey = mode == .click
        // White-on-glass reads well only over a dark material, whatever the system appearance.
        panel.appearance = NSAppearance(named: .darkAqua)
        let view = WheelView(kind: kind, files: files, clickable: mode == .click)
        view.onPick = { [weak self] operation, urls in self?.perform(operation, on: urls) }
        view.onDismiss = { [weak self] in self?.hide() }
        panel.contentView = view
        self.panel = panel
        wheel = view

        view.alphaValue = 0
        if mode == .click {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            // Clicking another window dismisses it, like a menu.
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                self?.hide()
            }
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
        if mode == .drag { startWatchdog() }
    }

    func switchTo(_ kind: WheelKind) { wheel?.kind = kind }

    func hide(animated: Bool = true) {
        watchdog?.invalidate()
        watchdog = nil
        buttonReleasedAt = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let panel else { return }
        self.panel = nil
        wheel = nil
        guard animated else { return panel.close() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.close() })
    }

    private func perform(_ operation: FileOperation, on urls: [URL]) {
        hide()
        FileOperationRunner.run(operation, on: urls)
    }

    /// A drag can end anywhere (dropped elsewhere, cancelled with Esc), so poll the button rather than rely on events.
    /// The short grace period lets a drop on the wheel arrive before it disappears.
    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 { self.buttonReleasedAt = nil; return }
            let released = self.buttonReleasedAt ?? Date()
            self.buttonReleasedAt = released
            if Date().timeIntervalSince(released) > 0.35 { self.hide() }
        }
    }
}

/// Draws the hub, the ring of bubbles and the wheel switcher, and handles drops, clicks and keys.
final class WheelView: NSView {
    static let size = CGSize(width: 360, height: 410)
    /// Centre of the disc in view coordinates.
    static let hub = CGPoint(x: 180, y: 230)
    private let discRadius: CGFloat = 172, ringRadius: CGFloat = 116, hubRadius: CGFloat = 60

    var onPick: ((FileOperation, [URL]) -> Void)?
    var onDismiss: (() -> Void)?
    var kind: WheelKind { didSet { reload() } }

    private let files: [URL]
    private let clickable: Bool
    private var operations: [FileOperation] = []
    private var hovered: Int? { didSet { if hovered != oldValue { redraw() } } }
    private var hoveredKind: WheelKind?
    private let icon: NSImage
    /// Frosted backgrounds are subviews, which always draw above a view's own drawing, so the content lives on top of them.
    private let canvas = WheelCanvas()

    init(kind: WheelKind, files: [URL], clickable: Bool) {
        self.kind = kind
        self.files = files
        self.clickable = clickable
        icon = files.count == 1 ? NSWorkspace.shared.icon(forFile: files[0].path) : NSWorkspace.shared.icon(for: .data)
        super.init(frame: CGRect(origin: .zero, size: WheelView.size))
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
        let blur = NSVisualEffectView(frame: discRect)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = NSImage(size: discRect.size, flipped: false) { rect in NSBezierPath(ovalIn: rect).fill(); return true }
        addSubview(blur, positioned: .below, relativeTo: nil)
        let pills = NSVisualEffectView(frame: pillsRect)
        pills.material = .hudWindow
        pills.blendingMode = .behindWindow
        pills.state = .active
        pills.wantsLayer = true
        pills.layer?.cornerRadius = pillsRect.height / 2
        pills.layer?.backgroundColor = NSColor(white: 0, alpha: 0.35).cgColor
        addSubview(pills, positioned: .below, relativeTo: nil)
        canvas.frame = bounds
        canvas.drawer = { [weak self] in self?.drawContent() }
        addSubview(canvas)
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var discRect: CGRect {
        CGRect(x: WheelView.hub.x - discRadius, y: WheelView.hub.y - discRadius, width: discRadius * 2, height: discRadius * 2)
    }
    private var pillsRect: CGRect { CGRect(x: 30, y: 4, width: WheelView.size.width - 60, height: 36) }

    private func reload() {
        operations = ConversionCatalog.operations(for: files, kind: kind)
        hovered = clickable && !operations.isEmpty ? 0 : nil
        redraw()
    }

    private func redraw() { canvas.needsDisplay = true }

    // MARK: - Geometry

    private var accent: NSColor {
        switch kind {
        case .convert: return NSColor(calibratedRed: 1, green: 0.55, blue: 0.16, alpha: 1)
        case .tools: return .systemBlue
        case .actions: return .systemGreen
        }
    }

    private var bubbleRadius: CGFloat {
        let n = CGFloat(max(operations.count, 1))
        return min(36, .pi * ringRadius / n - 5)
    }

    /// Bubbles start at twelve o'clock and run clockwise.
    private func bubbleCenter(_ index: Int) -> CGPoint {
        let angle = .pi / 2 - 2 * .pi * CGFloat(index) / CGFloat(max(operations.count, 1))
        return CGPoint(x: WheelView.hub.x + ringRadius * cos(angle), y: WheelView.hub.y + ringRadius * sin(angle))
    }

    private func bubble(at point: CGPoint) -> Int? {
        operations.indices.first { bubbleCenter($0).distance(to: point) <= bubbleRadius + 8 }
    }

    private func pillRect(_ kind: WheelKind) -> CGRect {
        let index = CGFloat(WheelKind.allCases.firstIndex(of: kind) ?? 0)
        let width = (pillsRect.width - 8) / CGFloat(WheelKind.allCases.count)
        return CGRect(x: pillsRect.minX + 4 + index * width, y: pillsRect.minY + 4, width: width, height: pillsRect.height - 8)
    }

    private func pill(at point: CGPoint) -> WheelKind? { WheelKind.allCases.first { pillRect($0).contains(point) } }

    // MARK: - Drawing

    private func drawContent() {
        let hub = WheelView.hub
        // Disc tint and rim.
        NSColor(white: 0, alpha: 0.42).setFill()
        NSBezierPath(ovalIn: discRect).fill()
        let rim = NSBezierPath(ovalIn: discRect.insetBy(dx: 0.5, dy: 0.5))
        accent.withAlphaComponent(0.55).setStroke()
        rim.lineWidth = 1.5
        rim.stroke()

        for (index, operation) in operations.enumerated() { drawBubble(operation, at: bubbleCenter(index), selected: index == hovered) }

        // Hub: file icon and what will happen.
        let hubRect = CGRect(x: hub.x - hubRadius, y: hub.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)
        NSColor(white: 0, alpha: 0.3).setFill()
        NSBezierPath(ovalIn: hubRect).fill()
        icon.draw(in: CGRect(x: hub.x - 20, y: hub.y + 6, width: 40, height: 40))
        let headline: String
        if let hovered, operations.indices.contains(hovered) { headline = operations[hovered].title } else if operations.isEmpty {
            headline = "Nothing here"
        } else { headline = kind.title }
        let caption = files.count == 1 ? files[0].lastPathComponent : "\(files.count) items"
        drawText(headline, in: CGRect(x: hub.x - hubRadius + 6, y: hub.y - 22, width: hubRadius * 2 - 12, height: 28),
                 size: 11, weight: .semibold, color: .white, lines: 2)
        drawText(caption, in: CGRect(x: hub.x - hubRadius + 10, y: hub.y - 38, width: hubRadius * 2 - 20, height: 14),
                 size: 9, weight: .regular, color: NSColor(white: 1, alpha: 0.6), lines: 1)
        if operations.isEmpty {
            let other = WheelKind.allCases.filter { $0 != kind }.map { "\($0.trigger.symbol) \($0.title)" }.joined(separator: " · ")
            drawText("Try \(other)", in: CGRect(x: hub.x - 120, y: hub.y + ringRadius - 10, width: 240, height: 16),
                     size: 11, weight: .medium, color: NSColor(white: 1, alpha: 0.7), lines: 1)
        }

        // Switcher: one pill per wheel with the key that opens it.
        for item in WheelKind.allCases {
            let rect = pillRect(item)
            let active = item == kind
            if active || item == hoveredKind {
                (active ? accent : NSColor(white: 1, alpha: 0.15)).setFill()
                NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            }
            drawText("\(item.trigger.symbol)  \(item.title)", in: rect.offsetBy(dx: 0, dy: -6), size: 12, weight: .semibold,
                     color: active ? .white : NSColor(white: 1, alpha: 0.75), lines: 1)
        }
    }

    private func drawBubble(_ operation: FileOperation, at center: CGPoint, selected: Bool) {
        let radius = bubbleRadius * (selected ? 1.14 : 1)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        (selected ? accent : NSColor(white: 1, alpha: 0.13)).setFill()
        NSBezierPath(ovalIn: rect).fill()
        if selected {
            NSColor(white: 1, alpha: 0.9).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            ring.stroke()
        }
        // Formats are clearest as big text; tools and actions get an icon above the label.
        if case .convert = operation {
            drawText(operation.label, in: CGRect(x: center.x - radius + 2, y: center.y - 9, width: radius * 2 - 4, height: 18),
                     size: max(10, radius * 0.4), weight: .heavy, color: .white, lines: 1)
            return
        }
        let iconSize = radius * 0.5
        if let symbol = NSImage(systemSymbolName: operation.symbol, accessibilityDescription: operation.title)?
            .withSymbolConfiguration(.init(pointSize: iconSize, weight: .semibold).applying(.init(paletteColors: [.white]))) {
            let s = symbol.size
            symbol.draw(in: CGRect(x: center.x - s.width / 2, y: center.y + 1, width: s.width, height: s.height))
        }
        drawText(operation.label, in: CGRect(x: center.x - radius + 2, y: center.y - radius * 0.62, width: radius * 2 - 4, height: 14),
                 size: max(8.5, radius * 0.3), weight: .bold, color: .white, lines: 1)
    }

    private func drawText(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, lines: Int) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = lines == 1 ? .byTruncatingMiddle : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = min(rect.height, string.boundingRect(with: CGSize(width: rect.width, height: rect.height), options: .usesLineFragmentOrigin).height)
        string.draw(with: CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // MARK: - Pointer

    private func track(_ point: CGPoint) {
        if let index = bubble(at: point) { hovered = index } else if !clickable { hovered = nil }
        let overPill = pill(at: point)
        if overPill != hoveredKind { hoveredKind = overPill; redraw() }
        // While dragging, resting on another wheel's pill switches to it: the keyboard may be busy holding the drag.
        if !clickable, let overPill, overPill != kind { kind = overPill }
    }

    override func mouseMoved(with event: NSEvent) { track(convert(event.locationInWindow, from: nil)) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let kind = pill(at: point) { return self.kind = kind }
        if let index = bubble(at: point) { onPick?(operations[index], files); return }
        if !discRect.contains(point) || point.distance(to: WheelView.hub) <= hubRadius { onDismiss?() }
    }

    // MARK: - Keyboard (click mode)

    override func keyDown(with event: NSEvent) {
        let count = operations.count
        switch Int(event.keyCode) {
        case 53: onDismiss?() // esc
        case 36, 76: // return, enter
            if let hovered, operations.indices.contains(hovered) { onPick?(operations[hovered], files) }
        case 123, 125: if count > 0 { hovered = ((hovered ?? 0) - 1 + count) % count } // left, down
        case 124, 126: if count > 0 { hovered = ((hovered ?? -1) + 1) % count } // right, up
        case 48: // tab cycles the wheels
            let all = WheelKind.allCases
            kind = all[((all.firstIndex(of: kind) ?? 0) + (event.modifierFlags.contains(.shift) ? all.count - 1 : 1)) % all.count]
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Drop target (drag mode)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(convert(sender.draggingLocation, from: nil))
        return hovered == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let hovered, operations.indices.contains(hovered) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? files
        onPick?(operations[hovered], urls.isEmpty ? files : urls)
        return true
    }
}

/// Transparent drawing layer above the wheel's blurred backgrounds; it never takes events itself.
private final class WheelCanvas: NSView {
    var drawer: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) { drawer?() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
