#if DEBUG
import AppKit

/// Development-only input automation, compiled out of Release builds.
/// `snapwise://debug-drag?x1=&y1=&x2=&y2=&hold=` performs a real mouse drag (CoreGraphics global coordinates)
/// so window-drag and file-drag behaviour can be exercised end to end (`tap=`, `x3`, `y3`: tap a modifier mid-drag, then move on); `debug-click?x=&y=[&x2=&y2=]` is a quick left click, optionally followed by a second one.
enum DebugAutomation {
    static func handle(command: String, url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func number(_ name: String) -> Double? { items.first { $0.name == name }?.value.flatMap(Double.init) }
        if command == "debug-rightclick", let x = number("x"), let y = number("y") {
            DispatchQueue.global().async {
                for type in [CGEventType.mouseMoved, .rightMouseDown, .rightMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .right)?.post(tap: .cghidEventTap)
                    usleep(120_000)
                }
            }
            return true
        }
        if command == "debug-click", let x = number("x"), let y = number("y") {
            DispatchQueue.global().async {
                // An optional second click (`x2`, `y2`) follows a second later, e.g. to pick an item from the menu the first opened;
                // URL commands are not delivered while a menu is tracking.
                var points = [CGPoint(x: x, y: y)]
                if let x2 = number("x2"), let y2 = number("y2") { points.append(CGPoint(x: x2, y: y2)) }
                for (index, point) in points.enumerated() {
                    if index > 0 { usleep(1_000_000) }
                    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                        usleep(type == .mouseMoved ? 150_000 : 40_000)
                    }
                }
            }
            return true
        }
        guard command == "debug-drag" else { return false }
        guard let x1 = number("x1"), let y1 = number("y1"), let x2 = number("x2"), let y2 = number("y2") else { return true }
        let hold = number("hold") ?? 0.5
        DispatchQueue.global().async {
            func post(_ type: CGEventType, _ x: Double, _ y: Double) {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(18_000)
            }
            post(.mouseMoved, x1, y1)
            usleep(150_000)
            post(.leftMouseDown, x1, y1)
            usleep(120_000)
            let steps = 40
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                post(.leftMouseDragged, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
            }
            // Keep nudging so drag events continue while the pointer rests on the target.
            func rest(_ seconds: Double, _ x: Double, _ y: Double) {
                for i in 0..<max(1, Int(seconds / 0.05)) {
                    post(.leftMouseDragged, x, y + Double(i % 2))
                    usleep(32_000)
                }
            }
            rest(hold, x2, y2)
            // Optional modifier tap mid-drag (`tap=shift|command|control|option`), then a move to `x3`,`y3` before dropping.
            var end = (x2, y2)
            if let name = items.first(where: { $0.name == "tap" })?.value {
                let keys: [String: (CGKeyCode, CGEventFlags)] = ["shift": (56, .maskShift), "command": (55, .maskCommand),
                                                                 "control": (59, .maskControl), "option": (58, .maskAlternate)]
                if let (code, flag) = keys[name] {
                    for down in [true, false] {
                        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
                        event?.type = .flagsChanged
                        event?.flags = down ? flag : []
                        event?.post(tap: .cghidEventTap)
                        usleep(90_000)
                    }
                }
                rest(0.6, x2, y2)
                if let x3 = number("x3"), let y3 = number("y3") {
                    for i in 1...20 { post(.leftMouseDragged, x2 + (x3 - x2) * Double(i) / 20, y2 + (y3 - y2) * Double(i) / 20) }
                    rest(number("hold3") ?? 0.6, x3, y3)
                    end = (x3, y3)
                }
            }
            post(.leftMouseUp, end.0, end.1)
        }
        return true
    }
}
#endif
