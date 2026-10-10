import AppKit
import os

/// Unified-log channel; inspect with `log stream --predicate 'subsystem == "com.tieuviettrongnghia.lumshot"'`.
/// Only counts, sizes and error text are logged, never captured content.
enum Log {
    static let app = Logger(subsystem: "com.tieuviettrongnghia.lumshot", category: "app")
}

/// Borderless floating panel used by every overlay; can take key focus without activating the app,
/// so the frontmost app keeps its active appearance while we draw on top of it.
final class OverlayPanel: NSPanel {
    var allowsKey = true

    init(frame: CGRect, level: NSWindow.Level = .statusBar, clickThrough: Bool = false) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = clickThrough
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Transient status message shown at the top of the active screen.
enum Toast {
    private static var panel: OverlayPanel?
    private static var hideWork: DispatchWorkItem?

    /// `detail` adds a wrapped preview under the headline (used for OCR results).
    static func show(_ message: String, detail: String? = nil, duration: TimeInterval = 2.2) {
        DispatchQueue.main.async {
            hideWork?.cancel()
            panel?.close()

            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .white
            label.lineBreakMode = .byTruncatingMiddle
            label.sizeToFit()
            var size = CGSize(width: min(label.frame.width, 520) + 32, height: label.frame.height + 18)

            var preview: NSTextField?
            if let detail, !detail.isEmpty {
                let field = NSTextField(wrappingLabelWithString: detail)
                field.font = .systemFont(ofSize: 12)
                field.textColor = NSColor(white: 1, alpha: 0.75)
                field.maximumNumberOfLines = 4
                field.lineBreakMode = .byTruncatingTail
                field.preferredMaxLayoutWidth = 420
                let fitted = field.sizeThatFits(CGSize(width: 420, height: 80))
                field.frame = CGRect(x: 16, y: 12, width: 420, height: min(fitted.height, 70))
                size = CGSize(width: 452, height: label.frame.height + field.frame.height + 30)
                preview = field
            }
            let screen = NSScreen.underMouse.visibleFrame
            let frame = CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 16, width: size.width, height: size.height)

            let p = OverlayPanel(frame: frame, clickThrough: true)
            p.allowsKey = false
            let bg = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
            bg.material = .hudWindow
            bg.state = .active
            bg.wantsLayer = true
            bg.layer?.cornerRadius = preview == nil ? size.height / 2 : 14
            bg.layer?.masksToBounds = true
            label.frame = CGRect(x: 16, y: size.height - label.frame.height - 9, width: size.width - 32, height: label.frame.height)
            bg.addSubview(label)
            if let preview { bg.addSubview(preview) }
            p.contentView = bg
            p.orderFrontRegardless()
            panel = p

            let work = DispatchWorkItem {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }, completionHandler: {
                    p.close()
                    if panel === p { panel = nil }
                })
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }
}
