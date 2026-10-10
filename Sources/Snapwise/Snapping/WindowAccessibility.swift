import AppKit
import ApplicationServices

/// Another app's window, driven through the Accessibility API. Frames are in CoreGraphics global space (top-left origin).
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    var frame: CGRect? {
        guard let position: CGPoint = WindowAX.value(of: element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = WindowAX.value(of: element, kAXSizeAttribute, .cgSize) else { return nil }
        return CGRect(origin: position, size: size)
    }

    var bundleIdentifier: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) }
    }

    func setFrame(_ rect: CGRect) {
        // Position–size–position: the first move gets the window onto the target display, where the size may then
        // be allowed to grow; the second move corrects any shift caused by the app clamping the size.
        setPosition(rect.origin)
        setSize(rect.size)
        setPosition(rect.origin)
    }
}

enum WindowAX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func value<T>(of element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let ref,
              CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        return AXValueGetValue(ref as! AXValue, type, result) ? result.pointee : nil
    }

    static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let ref,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    /// The window that has keyboard focus in the frontmost app.
    static func focusedWindow() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = elementAttribute(appElement, kAXFocusedWindowAttribute) ?? elementAttribute(appElement, kAXMainWindowAttribute) else { return nil }
        return AXWindow(element: window, pid: app.processIdentifier)
    }

    /// The UI element under a point in CoreGraphics global coordinates.
    static func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        return result == .success ? element : nil
    }

    /// The window containing the element under `point`.
    static func window(at point: CGPoint) -> AXWindow? {
        guard let hit = element(at: point) else { return nil }
        return window(containing: hit)
    }

    static func window(containing element: AXUIElement) -> AXWindow? {
        var current = element
        for _ in 0..<12 {
            if string(of: current, kAXRoleAttribute) == kAXWindowRole { return AXWindow(element: current, pid: pid(of: current)) }
            if let window = elementAttribute(current, kAXWindowAttribute) { return AXWindow(element: window, pid: pid(of: window)) }
            guard let parent = elementAttribute(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    static var pointerLocation: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: NSScreen.primaryHeight - p.y)
    }
}
