import AppKit
import AVFoundation

/// A mouse click during a recording; `x`/`y` are normalized to the recorded area with a top-left origin.
struct ClickEvent: Codable, Equatable {
    var t: Double
    var x: Double
    var y: Double
}

/// Records click positions for the video editor and optionally draws a ripple that ends up in the recording.
final class ClickTracker {
    private(set) var events: [ClickEvent] = []
    private let area: CGRect
    private let panel: OverlayPanel?
    private var monitor: Any?
    private let clock: () -> TimeInterval
    private let prefs = Prefs.shared

    /// `area` is the recorded rect in AppKit global coordinates; `clock` returns seconds since recording start.
    init(area: CGRect, screen: NSScreen, clock: @escaping () -> TimeInterval) {
        self.area = area
        self.clock = clock
        if prefs.recHighlightClicks {
            let panel = OverlayPanel(frame: screen.frame, level: .screenSaver, clickThrough: true)
            panel.allowsKey = false
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            panel.contentView = view
            panel.orderFrontRegardless()
            CaptureVisibility.include(panel, recordingOnly: true)
            self.panel = panel
        } else {
            panel = nil
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.clicked(at: NSEvent.mouseLocation)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let panel {
            CaptureVisibility.remove(panel)
            panel.close()
        }
    }

    private func clicked(at point: CGPoint) {
        guard area.contains(point) else { return }
        let time = clock()
        if time >= 0 {
            events.append(ClickEvent(t: time, x: Double((point.x - area.minX) / area.width), y: Double((area.maxY - point.y) / area.height)))
        }
        guard let panel, let layer = panel.contentView?.layer else { return }
        let size = CGFloat(prefs.clickSize)
        let local = CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: local.x - size / 2, y: local.y - size / 2, width: size, height: size)
        ring.path = CGPath(ellipseIn: CGRect(origin: .zero, size: ring.frame.size).insetBy(dx: 2, dy: 2), transform: nil)
        let color = NSColor(hex: prefs.clickColor)
        ring.fillColor = prefs.clickFilled ? color.withAlphaComponent(0.45).cgColor : NSColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 3
        layer.addSublayer(ring)

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        var animations: [CAAnimation] = [fade]
        if prefs.clickAnimated {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.4
            grow.toValue = 1.25
            animations.append(grow)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = 0.5
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }
}

/// Shows pressed keys near the bottom (or top) of the recorded area.
final class KeystrokeOverlay {
    private let panel: OverlayPanel
    private let label = NSTextField(labelWithString: "")
    private let backdrop = NSView()
    private let area: CGRect
    private var monitor: Any?
    private var hideWork: DispatchWorkItem?
    private var buffer = ""
    private var lastKeyTime = Date.distantPast
    private let prefs = Prefs.shared

    init?(area: CGRect) {
        // Observing other apps' key events requires the Accessibility permission.
        guard Permissions.ensureAccessibility() else {
            Toast.show("Grant Accessibility access to show keystrokes")
            return nil
        }
        self.area = area
        panel = OverlayPanel(frame: CGRect(x: area.midX - 100, y: area.minY + 40, width: 200, height: 44), level: .screenSaver, clickThrough: true)
        panel.allowsKey = false
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 10
        backdrop.layer?.backgroundColor = (prefs.keystrokeLight ? NSColor.white.withAlphaComponent(0.9) : NSColor.black.withAlphaComponent(0.75)).cgColor
        label.font = .systemFont(ofSize: CGFloat(prefs.keystrokeSize), weight: .semibold)
        label.textColor = prefs.keystrokeLight ? .black : .white
        label.alignment = .center
        backdrop.addSubview(label)
        panel.contentView = backdrop
        backdrop.alphaValue = 0
        // Must be on screen before the capture filter is built so it can be whitelisted.
        panel.orderFrontRegardless()
        CaptureVisibility.include(panel, recordingOnly: true)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] in self?.keyDown($0) }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hideWork?.cancel()
        CaptureVisibility.remove(panel)
        panel.close()
    }

    static func describe(_ event: NSEvent, commandsOnly: Bool) -> (text: String, isCommand: Bool)? {
        let flags = event.modifierFlags
        let isCommand = !flags.intersection([.command, .control, .option]).isEmpty
        if commandsOnly && !isCommand { return nil }
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 76: "⌤"]
        guard let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return nil }
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift), isCommand || special[event.keyCode] != nil { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return (text + key, isCommand)
    }

    private func keyDown(_ event: NSEvent) {
        guard let key = KeystrokeOverlay.describe(event, commandsOnly: prefs.keystrokeCommandsOnly) else { return }
        // Plain typing accumulates into a word; shortcuts replace the display.
        let continuing = Date().timeIntervalSince(lastKeyTime) < 1.2 && !key.isCommand && !buffer.isEmpty
        buffer = continuing ? String((buffer + key.text).suffix(24)) : key.text
        lastKeyTime = Date()
        label.stringValue = buffer
        label.sizeToFit()

        let size = CGSize(width: label.frame.width + 28, height: label.frame.height + 16)
        let y = prefs.keystrokePosition == "top" ? area.maxY - size.height - 40 : area.minY + 40
        panel.setFrame(CGRect(x: area.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        backdrop.frame = CGRect(origin: .zero, size: size)
        label.frame.origin = CGPoint(x: 14, y: 8)
        backdrop.alphaValue = 1

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.backdrop.animator().alphaValue = 0
            self?.buffer = ""
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}

/// Draggable webcam bubble that is captured as part of the screen recording.
final class CameraOverlay {
    private let panel: OverlayPanel
    private let session = AVCaptureSession()

    init?(area: CGRect) {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            Toast.show("No camera available")
            return nil
        }
        session.addInput(input)
        let prefs = Prefs.shared
        let side = CGFloat(prefs.cameraSize)
        let size = prefs.cameraShape == "wide" ? CGSize(width: side * 16 / 9, height: side) : CGSize(width: side, height: side)
        let inset: CGFloat = 24
        let left = prefs.cameraPosition.hasSuffix("Left"), top = prefs.cameraPosition.hasPrefix("top")
        let origin = CGPoint(x: left ? area.minX + inset : area.maxX - size.width - inset,
                             y: top ? area.maxY - size.height - inset : area.minY + inset)
        panel = OverlayPanel(frame: CGRect(origin: origin, size: size), level: .screenSaver)
        panel.allowsKey = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true

        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = prefs.cameraShape == "circle" ? side / 2 : 16
        preview.masksToBounds = true
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
        view.layer?.addSublayer(preview)
        panel.contentView = view
        panel.orderFrontRegardless()
        CaptureVisibility.include(panel, recordingOnly: true)

        let session = session
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
            } else {
                Toast.show("Camera access was denied")
            }
        }
    }

    func stop() {
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        CaptureVisibility.remove(panel)
        panel.close()
    }
}

/// Outline around the area being recorded; drawn just outside it so it never appears in the video.
final class RecordingBorder {
    private let panel: OverlayPanel

    init(area: CGRect) {
        panel = OverlayPanel(frame: area.insetBy(dx: -4, dy: -4), level: .screenSaver, clickThrough: true)
        panel.allowsKey = false
        let view = NSView(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.wantsLayer = true
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.systemRed.cgColor
        view.layer?.cornerRadius = 3
        panel.contentView = view
        panel.orderFrontRegardless()
    }

    func close() { panel.close() }
}
