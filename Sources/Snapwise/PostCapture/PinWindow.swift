import AppKit

/// A screenshot floating above all windows. Scroll to resize, ⌥-scroll for opacity, arrow keys to nudge.
final class PinWindowController: NSObject, NSWindowDelegate {
    private static var pins: [PinWindowController] = []
    static var hasLockedPins: Bool { pins.contains { $0.panel.ignoresMouseEvents } }

    private let panel: OverlayPanel
    private let image: CGImage
    private let scale: CGFloat
    private let naturalSize: CGSize

    static func pin(image: CGImage, scale: CGFloat) {
        let controller = PinWindowController(image: image, scale: scale)
        pins.append(controller)
        controller.panel.makeKeyAndOrderFront(nil)
    }

    static func unlockAll() {
        pins.forEach { $0.setLocked(false) }
        MenuBarController.shared.rebuildMenu()
    }

    private init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        let screen = NSScreen.underMouse.visibleFrame
        let full = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fitted = full.width > screen.width * 0.8 || full.height > screen.height * 0.8
            ? Geo.aspectFit(full, in: CGSize(width: screen.width * 0.8, height: screen.height * 0.8)) : full
        naturalSize = fitted
        let frame = CGRect(x: screen.midX - fitted.width / 2, y: screen.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
        panel = OverlayPanel(frame: frame, level: .floating)
        super.init()
        panel.styleMask.insert(.resizable)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentAspectRatio = fitted
        panel.minSize = CGSize(width: 40, height: 40 * fitted.height / fitted.width)
        panel.delegate = self
        let view = PinView(controller: self)
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        panel.contentView = view
        panel.makeFirstResponder(view)
    }

    func windowWillClose(_ notification: Notification) {
        PinWindowController.pins.removeAll { $0 === self }
        MenuBarController.shared.rebuildMenu()
    }

    fileprivate func resize(by factor: CGFloat) {
        let old = panel.frame
        let width = max(40, min(old.width * factor, naturalSize.width * 6))
        let size = CGSize(width: width, height: width * naturalSize.height / naturalSize.width)
        panel.setFrame(CGRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }

    fileprivate func nudge(dx: CGFloat, dy: CGFloat) {
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
    }

    fileprivate func adjustOpacity(by delta: CGFloat) {
        panel.alphaValue = max(0.15, min(1, panel.alphaValue + delta))
    }

    fileprivate func setLocked(_ locked: Bool) {
        // A locked pin lets clicks through to the apps underneath; unlock from the menu bar.
        panel.ignoresMouseEvents = locked
    }

    fileprivate func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Copy", #selector(copyImage)))
        menu.addItem(item("Save", #selector(saveImage)))
        menu.addItem(item("Annotate", #selector(annotate)))
        menu.addItem(.separator())
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacity.submenu = NSMenu()
        for percent in [100, 75, 50, 25] {
            let entry = item("\(percent)%", #selector(setOpacity(_:)))
            entry.tag = percent
            entry.state = Int((panel.alphaValue * 100).rounded()) == percent ? .on : .off
            opacity.submenu?.addItem(entry)
        }
        menu.addItem(opacity)
        menu.addItem(item("Actual Size", #selector(resetSize)))
        menu.addItem(item("Lock (click-through)", #selector(lock)))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(close)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copyImage() { Output.copy(image: image, scale: scale) }
    @objc private func saveImage() {
        if let url = Output.save(image: image, scale: scale) { Toast.show("Saved to \(url.lastPathComponent)") }
    }
    @objc private func annotate() {
        if let item = HistoryStore.shared.add(image: image, scale: scale) { EditorWindowController.open(item: item) }
    }
    @objc private func setOpacity(_ sender: NSMenuItem) { panel.alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func resetSize() { resize(by: naturalSize.width / panel.frame.width) }
    @objc private func lock() {
        setLocked(true)
        MenuBarController.shared.rebuildMenu()
        Toast.show("Pin locked — unlock it from the Snapwise menu")
    }
    @objc fileprivate func close() { panel.close() }
}

private final class PinView: NSView {
    private unowned let controller: PinWindowController

    init(controller: PinWindowController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func menu(for event: NSEvent) -> NSMenu? { controller.makeMenu() }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        if event.modifierFlags.contains(.option) {
            controller.adjustOpacity(by: delta > 0 ? 0.04 : -0.04)
        } else {
            controller.resize(by: delta > 0 ? 1.04 : 0.96)
        }
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: controller.nudge(dx: -step, dy: 0)
        case 124: controller.nudge(dx: step, dy: 0)
        case 125: controller.nudge(dx: 0, dy: -step)
        case 126: controller.nudge(dx: 0, dy: step)
        case 24: controller.resize(by: 1.1) // =
        case 27: controller.resize(by: 0.9) // -
        case 53: controller.close() // esc
        default: super.keyDown(with: event)
        }
    }
}
