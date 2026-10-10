import AppKit
import ApplicationServices

/// Modifier-key options for moving/resizing the window under the pointer without clicking.
enum GestureModifier: String, CaseIterable {
    case off, controlOption = "ctrl+opt", optionCommand = "opt+cmd", controlCommand = "ctrl+cmd"
    case controlOptionCommand = "ctrl+opt+cmd", optionShift = "opt+shift", fn

    var label: String {
        switch self {
        case .off: return "Off"
        case .controlOption: return "⌃⌥"
        case .optionCommand: return "⌥⌘"
        case .controlCommand: return "⌃⌘"
        case .controlOptionCommand: return "⌃⌥⌘"
        case .optionShift: return "⌥⇧"
        case .fn: return "fn"
        }
    }

    var flags: NSEvent.ModifierFlags? {
        switch self {
        case .off: return nil
        case .controlOption: return [.control, .option]
        case .optionCommand: return [.option, .command]
        case .controlCommand: return [.control, .command]
        case .controlOptionCommand: return [.control, .option, .command]
        case .optionShift: return [.option, .shift]
        case .fn: return [.function]
        }
    }
}

/// Hold a modifier combination and move the pointer to move or resize the window underneath it.
final class ModifierDragMonitor {
    private enum Mode { case move, resize }

    private var monitors: [Any] = []
    private var mode: Mode?
    private var window: AXWindow?
    private var startFrame = CGRect.zero
    private var startPointer = CGPoint.zero
    private var lastApplied = Date.distantPast
    private let prefs = Prefs.shared
    private let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]

    func start() {
        guard monitors.isEmpty else { return }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in self?.flagsChanged($0) },
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.mouseMoved() },
        ].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        mode = nil
        window = nil
    }

    private func flagsChanged(_ event: NSEvent) {
        let held = event.modifierFlags.intersection(relevant)
        let next: Mode?
        if let move = GestureModifier(rawValue: prefs.snapMoveModifier)?.flags, held == move {
            next = .move
        } else if let resize = GestureModifier(rawValue: prefs.snapResizeModifier)?.flags, held == resize {
            next = .resize
        } else {
            next = nil
        }
        guard next != nil else {
            mode = nil
            window = nil
            return
        }
        let pointer = WindowAX.pointerLocation
        guard WindowAX.isTrusted, let target = WindowAX.window(at: pointer), target.pid != getpid(),
              !SnapManager.shared.isExcluded(target), let frame = target.frame else { return }
        mode = next
        window = target
        startFrame = frame
        startPointer = pointer
    }

    private func mouseMoved() {
        guard let mode, let window, Date().timeIntervalSince(lastApplied) > 1.0 / 60 else { return }
        lastApplied = Date()
        let pointer = WindowAX.pointerLocation
        let delta = pointer - startPointer
        switch mode {
        case .move:
            window.setPosition(startFrame.origin + delta)
        case .resize:
            window.setSize(CGSize(width: max(120, startFrame.width + delta.x), height: max(80, startFrame.height + delta.y)))
        }
    }
}

/// Right- or middle-clicking a window's close / minimize / zoom button runs a configurable snap.
final class TitlebarButtonTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Button-down events we consumed; their matching button-up must be swallowed too.
    fileprivate var swallowUp = Set<Int64>()

    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TitlebarButtonTap>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        swallowUp = []
    }

    /// Returns true when the event should be swallowed.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        if type == .rightMouseUp || type == .otherMouseUp { return swallowUp.remove(button) != nil }
        let middle = type == .otherMouseDown
        if middle && button != 2 { return false }

        // Accessibility hit-testing can take tens of milliseconds in some apps and would delay every right-click
        // system-wide, so first make sure the pointer is over the top-left corner of a window at all.
        guard TitlebarButtonTap.isNearWindowButtons(event.location),
              let element = WindowAX.element(at: event.location),
              let subrole = WindowAX.string(of: element, kAXSubroleAttribute),
              let key = TitlebarButtonTap.prefKey(subrole: subrole, middle: middle),
              let position = SnapPosition(rawValue: UserDefaults.standard.string(forKey: key) ?? TitlebarButtonTap.defaults[key] ?? ""),
              let window = WindowAX.window(containing: element), !SnapManager.shared.isExcluded(window) else { return false }
        swallowUp.insert(button)
        DispatchQueue.main.async { SnapManager.shared.snap(position, window: window) }
        return true
    }

    static func isNearWindowButtons(_ point: CGPoint) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.contains(point) else { continue }
            // Only the frontmost window under the pointer matters.
            return point.y - bounds.minY <= 48 && point.x - bounds.minX <= 120
        }
        return false
    }

    static let buttons: [(title: String, subrole: String, key: String)] = [
        ("Zoom button (green)", kAXZoomButtonSubrole, "Zoom"),
        ("Minimize button (yellow)", kAXMinimizeButtonSubrole, "Minimize"),
        ("Close button (red)", kAXCloseButtonSubrole, "Close"),
    ]

    static let defaults: [String: String] = ["titlebarZoomRight": SnapPosition.maximize.rawValue]

    static func prefKey(subrole: String, middle: Bool) -> String? {
        // The zoom button reports a full-screen subrole on windows that support full screen.
        let normalized = subrole == kAXFullScreenButtonSubrole ? kAXZoomButtonSubrole : subrole
        guard let button = buttons.first(where: { $0.subrole == normalized }) else { return nil }
        return "titlebar\(button.key)\(middle ? "Middle" : "Right")"
    }
}

/// Starts and stops the snapping monitors according to preferences and the Accessibility permission.
final class SnapController {
    static let shared = SnapController()

    private let drag = DragSnapMonitor()
    private let modifier = ModifierDragMonitor()
    private let titlebar = TitlebarButtonTap()
    private var trustPoll: Timer?
    private let prefs = Prefs.shared

    /// Call at launch and whenever a snapping preference changes.
    func refresh() {
        trustPoll?.invalidate()
        trustPoll = nil
        guard prefs.snapEnabled else { return stopAll() }
        guard WindowAX.isTrusted else {
            stopAll()
            // Monitors cannot work until the user grants access; pick it up without needing a relaunch.
            trustPoll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                if WindowAX.isTrusted { self?.refresh() }
            }
            return
        }
        if prefs.snapDrag { drag.start() } else { drag.stop() }
        askAboutNativeTilingOnce()
        let usesModifiers = prefs.snapMoveModifier != GestureModifier.off.rawValue || prefs.snapResizeModifier != GestureModifier.off.rawValue
        if usesModifiers { modifier.start() } else { modifier.stop() }
        if prefs.snapTitlebarButtons { titlebar.start() } else { titlebar.stop() }
    }

    /// macOS tiles on the same edge drags; ask once which of the two should handle them.
    private func askAboutNativeTilingOnce() {
        guard prefs.snapDrag, !prefs.snapNativeTilingAsked, NativeTiling.isEnabled, !AppDelegate.isRunningTests else { return }
        prefs.snapNativeTilingAsked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let alert = NSAlert()
            alert.messageText = "Let Snapwise handle dragging windows to screen edges?"
            alert.informativeText = "macOS has its own edge tiling switched on. With both active, a window dragged to an edge is moved twice and can jump. "
                + "Snapwise can turn the macOS feature off (you can turn it back on in System Settings › Desktop & Dock)."
            alert.addButton(withTitle: "Turn Off macOS Tiling")
            alert.addButton(withTitle: "Keep Both")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { NativeTiling.setEnabled(false) }
        }
    }

    private func stopAll() {
        drag.stop()
        modifier.stop()
        titlebar.stop()
    }
}
