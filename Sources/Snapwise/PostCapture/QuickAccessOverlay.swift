import AppKit
import SwiftUI

/// Floating stack of capture thumbnails in a screen corner.
final class QuickAccessManager {
    static let shared = QuickAccessManager()

    private struct Card {
        var item: CaptureItem
        let panel: OverlayPanel
        var autoClose: DispatchWorkItem?
    }

    private var cards: [Card] = []
    private var recentlyClosed: [CaptureItem] = []
    private var screen: NSScreen = .underMouse
    private let prefs = Prefs.shared
    private let maxCards = 5

    /// Temporarily hides every card without closing them.
    var isHidden = false {
        didSet { cards.forEach { isHidden ? $0.panel.orderOut(nil) : $0.panel.orderFrontRegardless() } }
    }

    var canRestore: Bool { !recentlyClosed.isEmpty }

    func show(_ item: CaptureItem) {
        // Re-showing an item (e.g. after editing) swaps its card in place instead of swiping it away.
        if let index = cards.firstIndex(where: { $0.item.id == item.id }) { remove(at: index, remember: false, animated: false) }
        if cards.isEmpty { screen = .underMouse }
        let width = CGFloat(prefs.overlaySize)
        let size = CGSize(width: width, height: (width * 0.64).rounded())
        let panel = OverlayPanel(frame: CGRect(origin: .zero, size: size), level: .floating)
        panel.allowsKey = false
        panel.hasShadow = true
        let card = QuickAccessCardView(item: item, thumbnail: HistoryStore.shared.thumbnail(for: item), size: size)
        card.onClose = { [weak self] in self?.close(item) }
        card.onCopy = { [weak self] in
            ItemActions.copy(item)
            if self?.prefs.overlayCloseAfterCopy == true { self?.close(item) }
        }
        card.onSave = { [weak self] in
            if ItemActions.save(item), self?.prefs.overlayCloseAfterSave == true { self?.close(item) }
        }
        card.onDragEnded = { [weak self] dropped in
            if dropped, self?.prefs.overlayCloseAfterDrag == true { self?.close(item) }
        }
        panel.contentView = card

        var entry = Card(item: item, panel: panel)
        if prefs.overlayAutoClose {
            let work = DispatchWorkItem { [weak self] in self?.close(item) }
            entry.autoClose = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(max(1, prefs.overlayAutoCloseSeconds)), execute: work)
        }
        cards.insert(entry, at: 0)
        while cards.count > maxCards { remove(at: cards.count - 1, remember: true, animated: false) }
        layout(animated: true)
        guard !isHidden else { return }
        // Slide in from the screen edge it is docked to.
        let target = panel.frame
        panel.setFrame(target.offsetBy(dx: prefs.overlayOnLeft ? -(size.width + 40) : size.width + 40, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Re-renders a card after its capture was edited.
    func refresh(_ item: CaptureItem) {
        guard cards.contains(where: { $0.item.id == item.id }) else { return }
        show(item)
    }

    func close(_ item: CaptureItem, remember: Bool = true) {
        guard let index = cards.firstIndex(where: { $0.item.id == item.id }) else { return }
        remove(at: index, remember: remember)
        layout(animated: true)
    }

    func restoreRecentlyClosed() {
        while let item = recentlyClosed.popLast() {
            if HistoryStore.shared.items.contains(where: { $0.id == item.id }) { return show(item) }
        }
        Toast.show("Nothing to restore")
    }

    private func remove(at index: Int, remember: Bool, animated: Bool = true) {
        let card = cards.remove(at: index)
        card.autoClose?.cancel()
        animated ? swipeAway(card.panel) : card.panel.close()
        if remember {
            recentlyClosed.append(card.item)
            MenuBarController.shared.rebuildMenu()
        }
    }

    /// Slides a closing card off the screen edge it is docked to while fading it out, then closes it.
    private func swipeAway(_ panel: OverlayPanel) {
        guard panel.isVisible, !isHidden, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return panel.close() }
        panel.ignoresMouseEvents = true
        let frame = panel.frame
        let target = frame.offsetBy(dx: prefs.overlayOnLeft ? -(frame.width + 40) : frame.width + 40, dy: 0)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.close() })
    }

    private func layout(animated: Bool) {
        let area = screen.visibleFrame
        var y = area.minY + 20
        for card in cards {
            let size = card.panel.frame.size
            let x = prefs.overlayOnLeft ? area.minX + 20 : area.maxX - size.width - 20
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            if animated, card.panel.isVisible {
                card.panel.animator().setFrame(frame, display: true)
            } else {
                card.panel.setFrame(frame, display: true)
            }
            y += size.height + 12
        }
    }
}

/// Click target that reacts on the first click even while another app is active.
/// Built in AppKit on purpose: SwiftUI hover and buttons are unreliable inside a non-activating panel.
final class CardButton: NSView {
    private let action: () -> Void
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let isPill: Bool
    private var hovering = false { didSet { refresh() } }
    private var pressed = false { didSet { refresh() } }

    init(title: String? = nil, symbol: String? = nil, help: String, action: @escaping () -> Void) {
        self.action = action
        isPill = title != nil
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = help
        setAccessibilityRole(.button)
        setAccessibilityLabel(help)
        if let title {
            label.stringValue = title
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .black
            label.alignment = .center
            addSubview(label)
        } else if let symbol {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            icon.contentTintColor = .white
            addSubview(icon)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        label.sizeToFit()
        label.frame = CGRect(x: 0, y: (bounds.height - label.frame.height) / 2, width: bounds.width, height: label.frame.height)
        icon.frame = bounds.insetBy(dx: 6, dy: 6)
    }

    private func refresh() {
        let color: NSColor
        if isPill {
            color = pressed ? NSColor(white: 0.72, alpha: 1) : (hovering ? .white : NSColor(white: 1, alpha: 0.88))
        } else {
            color = pressed ? NSColor(white: 1, alpha: 0.45) : (hovering ? NSColor(white: 1, alpha: 0.3) : NSColor(white: 0, alpha: 0.55))
        }
        layer?.backgroundColor = color.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseDragged(with event: NSEvent) { pressed = bounds.contains(convert(event.locationInWindow, from: nil)) }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
        pressed = false
        // Deferred: the action may close the panel this view lives in.
        if inside { DispatchQueue.main.async(execute: action) }
    }
}

/// One thumbnail in the overlay: hover shows the actions, the background drags the file out.
final class QuickAccessCardView: NSView, NSDraggingSource {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?

    private let item: CaptureItem
    private let thumbnail: NSImage?
    private let controls = NSView()
    private let badge = NSImageView()
    private var mouseDownPoint: CGPoint?
    private var swipeDistance: CGFloat = 0

    init(item: CaptureItem, thumbnail: NSImage?, size: CGSize) {
        self.item = item
        self.thumbnail = thumbnail
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.3).cgColor

        let image = NSImageView(frame: bounds.insetBy(dx: 4, dy: 4))
        image.image = thumbnail
        image.imageScaling = .scaleProportionallyUpOrDown
        image.unregisterDraggedTypes() // an image well would swallow our own drag gestures
        addSubview(image)

        if item.kind != .screenshot {
            badge.image = NSImage(systemSymbolName: item.kind == .video ? "play.circle.fill" : "photo.stack.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 28, weight: .regular))
            badge.contentTintColor = .white
            badge.frame = CGRect(x: bounds.midX - 20, y: bounds.midY - 20, width: 40, height: 40)
            addSubview(badge)
        }
        buildControls()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildControls() {
        controls.frame = bounds
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
        controls.isHidden = true
        addSubview(controls)

        let pill = CGSize(width: 92, height: 28), gap: CGFloat = 8
        let copy = CardButton(title: "Copy", help: "Copy to clipboard") { [weak self] in self?.onCopy?() }
        copy.frame = CGRect(x: bounds.midX - pill.width / 2, y: bounds.midY + gap / 2, width: pill.width, height: pill.height)
        let save = CardButton(title: "Save", help: "Save to disk") { [weak self] in self?.onSave?() }
        save.frame = CGRect(x: bounds.midX - pill.width / 2, y: bounds.midY - gap / 2 - pill.height, width: pill.width, height: pill.height)
        controls.addSubview(copy)
        controls.addSubview(save)

        let side: CGFloat = 28, margin: CGFloat = 7
        func corner(_ symbol: String, _ help: String, left: Bool, top: Bool, _ action: @escaping () -> Void) {
            let button = CardButton(symbol: symbol, help: help, action: action)
            button.frame = CGRect(x: left ? margin : bounds.maxX - side - margin, y: top ? bounds.maxY - side - margin : margin, width: side, height: side)
            controls.addSubview(button)
        }
        corner("xmark", "Close", left: true, top: true) { [weak self] in self?.onClose?() }
        if item.kind == .screenshot {
            corner("pin.fill", "Pin to screen", left: false, top: true) { [item] in ItemActions.pin(item) }
        }
        corner("pencil", item.kind == .screenshot ? "Annotate" : "Edit", left: true, top: false) { [item] in ItemActions.edit(item) }
        corner("folder.fill", "Show in Finder", left: false, top: false) { [item] in ItemActions.reveal(item) }

        let info = NSTextField(labelWithString: item.infoText)
        info.font = .systemFont(ofSize: 9, weight: .medium)
        info.textColor = NSColor(white: 1, alpha: 0.85)
        info.alignment = .center
        info.lineBreakMode = .byTruncatingMiddle
        info.frame = CGRect(x: side + margin + 4, y: margin + 7, width: bounds.width - 2 * (side + margin + 4), height: 12)
        controls.addSubview(info)
    }

    // MARK: - Hover

    private func setControlsVisible(_ visible: Bool) {
        controls.isHidden = !visible
        badge.isHidden = visible
    }

    override func mouseEntered(with event: NSEvent) { setControlsVisible(true) }
    override func mouseExited(with event: NSEvent) { setControlsVisible(false) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The pointer is often already over the corner when a card appears; no "entered" event fires then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let window = self.window else { return }
            if window.frame.contains(NSEvent.mouseLocation) { self.setControlsVisible(true) }
        }
    }

    // MARK: - Mouse: double-click edits, dragging exports the file

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            mouseDownPoint = nil
            return ItemActions.edit(item)
        }
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, start.distance(to: event.locationInWindow) > 5,
              let url = ItemActions.stagedURL(for: item) else { return }
        mouseDownPoint = nil
        let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        dragItem.setDraggingFrame(bounds, contents: thumbnail)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(operation != [])
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        if event.phase == .began { swipeDistance = 0 }
        swipeDistance += event.scrollingDeltaX
        if abs(swipeDistance) > 60 {
            swipeDistance = 0
            onClose?()
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ handler: @escaping () -> Void) {
            let entry = ClosureMenuItem(title: title, handler: handler)
            menu.addItem(entry)
        }
        add("Copy") { [weak self] in self?.onCopy?() }
        add("Save") { [weak self] in self?.onSave?() }
        add(item.kind == .screenshot ? "Annotate" : "Edit") { [item] in ItemActions.edit(item) }
        if item.kind == .screenshot {
            add("Pin to Screen") { [item] in ItemActions.pin(item) }
            add("Copy Text (OCR)") { [item] in ItemActions.copyText(item) }
        }
        add("Show in Finder") { [item] in ItemActions.reveal(item) }
        menu.addItem(.separator())
        add("Delete") { [weak self, item] in
            self?.onClose?()
            HistoryStore.shared.delete(item)
        }
        return menu
    }
}

/// Menu item that runs a closure, so small context menus need no selector plumbing.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}
