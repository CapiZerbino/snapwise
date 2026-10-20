import AppKit

/// Opens a wheel when a modifier is tapped while files are being dragged — in Finder, on the desktop or in any app.
/// A tap is the key pressed and released on its own within a short time, so holding ⌘ or ⌥ to change what a drop
/// does in Finder keeps working.
final class FileDragMonitor {
    static let shared = FileDragMonitor()

    private var monitors: [Any] = []
    private var dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var press: (trigger: WheelTrigger, at: Date)?
    private var heldFlags: NSEvent.ModifierFlags = []
    private let tapLimit: TimeInterval = 0.45

    func refresh() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        guard Prefs.shared.convertEnabled else { return ConvertWheel.shared.hide(animated: false) }
        let mouseDown: (NSEvent) -> Void = { [weak self] _ in self?.dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount }
        let flags: (NSEvent) -> Void = { [weak self] in self?.flagsChanged($0) }
        let key: (NSEvent) -> Void = { [weak self] in self?.keyDown($0) }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: mouseDown),
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: key),
            // Drags that start in Snapwise itself (a Quick Access card, the editor) only reach local monitors.
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { mouseDown($0); return $0 },
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 },
        ].compactMap { $0 }
    }

    /// The files of the drag in progress, or nil when the mouse is not dragging files.
    static func draggedFiles(sinceChangeCount count: Int) -> [URL]? {
        let pasteboard = NSPasteboard(name: .drag)
        guard NSEvent.pressedMouseButtons & 1 != 0, pasteboard.changeCount != count,
              let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return nil }
        return urls
    }

    private func flagsChanged(_ event: NSEvent) {
        let now = event.modifierFlags.intersection([.shift, .command, .control, .option])
        defer { heldFlags = now }
        if heldFlags.isEmpty, let trigger = WheelTrigger.only(in: now) {
            press = (trigger, Date())
        } else if now.isEmpty, let press, Date().timeIntervalSince(press.at) < tapLimit {
            self.press = nil
            tapped(press.trigger)
        } else if !now.isEmpty {
            press = nil // a combination, or a second key joined in: not a tap
        }
    }

    private func keyDown(_ event: NSEvent) {
        press = nil // ⌘C and friends are shortcuts, not taps
        if event.keyCode == 53, ConvertWheel.shared.isVisible { ConvertWheel.shared.hide() }
    }

    private func tapped(_ trigger: WheelTrigger) {
        guard let kind = WheelKind.kind(for: trigger) else { return }
        if ConvertWheel.shared.isVisible { return ConvertWheel.shared.switchTo(kind) }
        guard let files = FileDragMonitor.draggedFiles(sinceChangeCount: dragCountAtMouseDown) else { return }
        ConvertWheel.shared.show(kind, files: files, at: NSEvent.mouseLocation, mode: .drag)
    }

    /// Convert Files…: pick files, then use the same wheel by clicking.
    static func chooseFiles() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose files to convert, process or share"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let screen = NSScreen.underMouse.visibleFrame
        ConvertWheel.shared.show(.convert, files: panel.urls, at: CGPoint(x: screen.midX, y: screen.midY), mode: .click)
    }
}
