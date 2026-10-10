import AppKit
import SwiftUI

/// Shortcut field: click it, press a combination. Shows held modifiers live; ✕ clears, Esc cancels.
final class ShortcutField: NSView {
    var appAction: AppAction = .captureArea { didSet { needsDisplay = true } }
    private var recording = false { didSet { needsDisplay = true } }
    private var heldModifiers = "" { didSet { needsDisplay = true } }
    private var monitor: Any?
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var hotkey: Hotkey? { HotkeyManager.shared.hotkey(for: appAction) }
    private var clearZone: CGRect { CGRect(x: bounds.maxX - 24, y: 0, width: 24, height: bounds.height) }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !recording, hotkey != nil, clearZone.contains(point) {
            HotkeyManager.shared.setHotkey(nil, for: appAction)
            needsDisplay = true
        } else if recording {
            endRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        recording = true
        heldModifiers = ""
        // Existing hotkeys would otherwise swallow the combination being typed.
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil // keep the keystroke away from menus and text fields while recording
        }
    }

    private func endRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyManager.shared.registerAll()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .flagsChanged {
            heldModifiers = Hotkey.symbols(for: flags)
            return
        }
        if flags.isEmpty, event.keyCode == 53 { return endRecording() }
        if flags.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
            endRecording()
            return HotkeyManager.shared.setHotkey(nil, for: appAction)
        }
        guard let hotkey = Hotkey(event: event) else { return NSSound.beep() }
        endRecording()
        HotkeyManager.shared.setHotkey(hotkey, for: appAction)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return endRecording() }
        // Switching apps or closing Settings must not leave every hotkey unregistered.
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowLostFocus), name: name, object: window)
        }
    }

    @objc private func windowLostFocus() { endRecording() }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).setFill()
        shape.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = recording ? 2 : 1
        shape.stroke()

        let text: String, color: NSColor
        if recording {
            text = heldModifiers.isEmpty ? "Press shortcut…" : heldModifiers.map(String.init).joined(separator: " ")
            color = .controlAccentColor
        } else if let hotkey {
            text = (Hotkey.symbols(for: hotkey.cocoaModifiers).map(String.init) + [hotkey.keyName]).joined(separator: " ")
            color = .labelColor
        } else {
            text = "Click to record"
            color = .tertiaryLabelColor
        }
        let showsClear = !recording && hotkey != nil
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color])
        let size = string.size()
        let width = bounds.width - (showsClear ? 20 : 0)
        string.draw(at: CGPoint(x: (width - size.width) / 2, y: (bounds.height - size.height) / 2))

        if showsClear, let icon = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut") {
            let tinted = icon.withSymbolConfiguration(.init(paletteColors: [hovering ? .secondaryLabelColor : .tertiaryLabelColor])) ?? icon
            tinted.draw(in: CGRect(x: bounds.maxX - 21, y: (bounds.height - 14) / 2, width: 14, height: 14))
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let action: AppAction
    /// Changes whenever hotkeys are re-registered, forcing a redraw.
    let revision: Int

    func makeNSView(context: Context) -> ShortcutField {
        let field = ShortcutField(frame: .zero)
        field.appAction = action
        return field
    }

    func updateNSView(_ nsView: ShortcutField, context: Context) {
        nsView.appAction = action
        nsView.needsDisplay = true
    }
}
