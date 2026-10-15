import AppKit
import ApplicationServices

/// Moves and resizes windows to snap positions and remembers their previous frames for "restore".
final class SnapManager {
    static let shared = SnapManager()

    private struct Record {
        let element: AXUIElement
        let original: CGRect
        var snapped: CGRect
    }

    private var records: [Record] = []
    private let prefs = Prefs.shared
    private let feedback = SnapPreview()

    /// Usable area (below the menu bar, beside the Dock) of the display holding most of `frame`, in CG coordinates.
    func area(containing frame: CGRect) -> (screen: NSScreen, area: CGRect)? {
        let appKit = Geo.flipGlobal(frame)
        let screen = NSScreen.screens.max { $0.frame.intersection(appKit).width * $0.frame.intersection(appKit).height
            < $1.frame.intersection(appKit).width * $1.frame.intersection(appKit).height } ?? NSScreen.main
        return screen.map { ($0, Geo.flipGlobal($0.visibleFrame)) }
    }

    func isExcluded(_ window: AXWindow) -> Bool {
        guard let id = window.bundleIdentifier else { return false }
        return prefs.snapExcluded.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == id }
    }

    /// Snaps the focused window (or `target`) to `position`.
    func snap(_ position: SnapPosition, window target: AXWindow? = nil) {
        guard ensureAccess() else { return }
        guard let window = target ?? WindowAX.focusedWindow(), let frame = window.frame, let (screen, area) = area(containing: frame) else {
            return Toast.show("No window to snap")
        }
        guard !isExcluded(window) else { return }
        let gap = CGFloat(prefs.snapGap)

        switch position {
        case .restore:
            guard let index = records.firstIndex(where: { CFEqual($0.element, window.element) }) else { return }
            window.setFrame(records[index].original)
            records.remove(at: index)
        case .center:
            // An oversized window is shrunk to fit so centering never pushes it off screen.
            let size = CGSize(width: min(frame.width, area.width - gap * 2), height: min(frame.height, area.height - gap * 2))
            apply(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height).roundedEdges,
                  to: window, flash: true)
        case .nextDisplay, .previousDisplay:
            let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return Toast.show("No other display") }
            let next = screens[(index + (position == .nextDisplay ? 1 : screens.count - 1)) % screens.count]
            apply(SnapGeometry.transfer(frame, from: area, to: Geo.flipGlobal(next.visibleFrame)), to: window, flash: true)
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            if let rect = SnapGeometry.moved(frame, to: position, in: area, gap: gap) { apply(rect, to: window, flash: true) }
        default:
            // Maximize acts as a toggle: pressing it on an already maximized window puts it back.
            if position == .maximize, let full = position.frame(in: area, gap: gap), full.isClose(to: frame, tolerance: 8),
               let index = records.firstIndex(where: { CFEqual($0.element, window.element) }) {
                window.setFrame(records[index].original)
                feedback.flash(records[index].original)
                records.remove(at: index)
                return
            }
            if let rect = SnapGeometry.nextFrame(for: position, current: frame, in: area, gap: gap, cycling: prefs.snapCycleSizes) {
                apply(rect, to: window, flash: true)
            }
        }
    }

    func snap(to custom: CustomSnapArea, on screen: NSScreen, window: AXWindow) {
        apply(SnapGeometry.frame(fractions: custom.fractions, in: Geo.flipGlobal(screen.visibleFrame), gap: CGFloat(prefs.snapGap)), to: window)
    }

    /// Sets the frame and records the pre-snap frame the first time a window is snapped.
    func apply(_ rect: CGRect, to window: AXWindow, flash: Bool = false) {
        guard let current = window.frame else { return }
        if flash { feedback.flash(rect) }
        if let index = records.firstIndex(where: { CFEqual($0.element, window.element) }) {
            // Still at its snapped spot: keep the original. Moved by hand since: that position is the new original.
            if !records[index].snapped.isClose(to: current) {
                records[index] = Record(element: window.element, original: current, snapped: rect)
            } else {
                records[index].snapped = rect
            }
        } else {
            records.append(Record(element: window.element, original: current, snapped: rect))
            if records.count > 80 { records.removeFirst() }
        }
        window.setFrame(rect)
        // Apps with a minimum size may end up hanging off the screen; pull them back in.
        if let actual = window.frame, let (_, area) = area(containing: rect) {
            var origin = actual.origin
            if actual.maxX > area.maxX { origin.x = max(area.minX, area.maxX - actual.width) }
            if actual.maxY > area.maxY { origin.y = max(area.minY, area.maxY - actual.height) }
            if origin != actual.origin { window.setPosition(origin) }
        }
        // Some apps finish their own move/animation after ours; check once more and correct any drift.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let settled = window.frame, !settled.isClose(to: rect, tolerance: 0.5),
                  self.records.contains(where: { CFEqual($0.element, window.element) && $0.snapped == rect }) else { return }
            window.setFrame(rect)
        }
    }

    /// The size a snapped window had before snapping, if it is still where we put it.
    func originalSize(ofSnapped window: AXWindow) -> CGSize? {
        guard let frame = window.frame, let record = records.first(where: { CFEqual($0.element, window.element) }),
              record.snapped.isClose(to: frame) else { return nil }
        return record.original.size
    }

    func forget(_ window: AXWindow) {
        records.removeAll { CFEqual($0.element, window.element) }
    }

    @discardableResult
    func ensureAccess() -> Bool {
        if WindowAX.isTrusted { return true }
        _ = Permissions.ensureAccessibility()
        Toast.show("Allow Snapwise under Accessibility to move windows", duration: 4)
        return false
    }
}

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
