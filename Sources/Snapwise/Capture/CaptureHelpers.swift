import AppKit
import ApplicationServices
import Vision

enum Permissions {
    /// Returns true when screen capture is allowed; otherwise triggers the system prompt and explains the next step.
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Snapwise needs Screen Recording permission"
        alert.informativeText = "Enable Snapwise in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch Snapwise."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    /// Needed to observe keystrokes and to post scroll events.
    static func ensureAccessibility(prompt: Bool = true) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
    }
}

/// Big on-screen countdown used by the self-timer and before recordings. Click it to cancel.
final class CountdownHUD: NSView {
    private static var current: OverlayPanel?
    private var remaining: Int
    private var timer: Timer?
    private let completion: (Bool) -> Void

    static func run(seconds: Int, on screen: NSScreen, completion: @escaping (Bool) -> Void) {
        cancel() // a replaced countdown must still report back, or its flow would hang
        guard seconds > 0 else { return completion(true) }
        let side: CGFloat = 140
        let frame = CGRect(x: screen.frame.midX - side / 2, y: screen.frame.midY - side / 2, width: side, height: side)
        let panel = OverlayPanel(frame: frame, level: .screenSaver)
        panel.allowsKey = false
        panel.contentView = CountdownHUD(seconds: seconds, side: side, completion: completion)
        panel.orderFrontRegardless()
        current = panel
    }

    /// Aborts the running countdown, reporting `false` to its owner.
    static func cancel() {
        (current?.contentView as? CountdownHUD)?.finish(false)
    }

    private init(seconds: Int, side: CGFloat, completion: @escaping (Bool) -> Void) {
        remaining = seconds
        self.completion = completion
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func tick() {
        remaining -= 1
        needsDisplay = true
        if remaining <= 0 { finish(true) }
    }

    private func finish(_ completed: Bool) {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        CountdownHUD.current?.close()
        CountdownHUD.current = nil
        // Let the window server drop the HUD before the capture starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [completion] in completion(completed) }
    }

    override func mouseDown(with event: NSEvent) { finish(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4)).fill()
        let str = NSAttributedString(string: "\(max(remaining, 1))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 64, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        let size = str.size()
        str.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// Covers the desktop icons with a copy of the wallpaper, one window per display.
enum DesktopIconsHider {
    private static var windows: [NSWindow] = []
    static var isHidden: Bool { !windows.isEmpty }

    static func toggle() { setHidden(!isHidden) }

    static func setHidden(_ hidden: Bool) {
        windows.forEach {
            CaptureVisibility.remove($0)
            $0.close()
        }
        windows = []
        guard hidden else { return }
        for screen in NSScreen.screens {
            // One level above the Finder's icon layer, still below every normal window.
            let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            let panel = OverlayPanel(frame: screen.frame, level: level, clickThrough: true)
            panel.allowsKey = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) {
                view.layer?.contents = image
                view.layer?.contentsGravity = .resizeAspectFill
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            CaptureVisibility.include(panel)
            windows.append(panel)
        }
    }
}

/// Places a window screenshot on the user's chosen backdrop and adds a drop shadow.
enum WindowBackgroundComposer {
    static func compose(window: CGImage, scale: CGFloat, screen: NSScreen?, prefs: Prefs = .shared) -> CGImage {
        let mode = prefs.windowBackground
        let transparent = mode == "transparent"
        if transparent && !prefs.windowShadow { return window }
        // A transparent shot only needs enough margin to hold the shadow.
        let padding = (transparent ? 56 : CGFloat(prefs.windowPadding)) * scale
        let size = CGSize(width: CGFloat(window.width) + padding * 2, height: CGFloat(window.height) + padding * 2)
        guard let ctx = CGContext.bitmap(width: Int(size.width), height: Int(size.height)) else { return window }
        let canvas = CGRect(origin: .zero, size: size)

        switch mode {
        case "solid":
            ctx.setFillColor(NSColor(hex: prefs.windowSolidColor).cgColor)
            ctx.fill(canvas)
        case "gradient":
            GradientPreset.at(prefs.windowGradientIndex).fill(canvas, in: ctx)
        case "wallpaper":
            if let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen), let wallpaper = NSImage(contentsOf: url)?.cgImage {
                let s = max(size.width / CGFloat(wallpaper.width), size.height / CGFloat(wallpaper.height))
                let w = CGFloat(wallpaper.width) * s, h = CGFloat(wallpaper.height) * s
                ctx.draw(wallpaper, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            } else {
                GradientPreset.at(prefs.windowGradientIndex).fill(canvas, in: ctx)
            }
        default: break
        }

        if prefs.windowShadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale, color: NSColor.black.withAlphaComponent(0.42).cgColor)
        }
        ctx.draw(window, in: CGRect(x: padding, y: padding, width: CGFloat(window.width), height: CGFloat(window.height)))
        return ctx.makeImage() ?? window
    }
}

enum TextRecognizer {
    /// Recognizes text and QR/barcode payloads on-device. Blocking; call off the main thread.
    static func recognize(_ image: CGImage) -> String {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        // Hints improve diacritics; the detector still handles other languages.
        let supported = (try? text.supportedRecognitionLanguages()) ?? []
        let wanted = Locale.preferredLanguages + ["vi-VT", "en-US"]
        var hints: [String] = []
        for code in wanted {
            let base = code.split(separator: "-").first.map(String.init) ?? code
            if let match = supported.first(where: { $0 == code || $0.hasPrefix(base + "-") }), !hints.contains(match) { hints.append(match) }
        }
        if !hints.isEmpty { text.recognitionLanguages = hints }
        let codes = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([text, codes])

        var lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let payloads = (codes.results ?? []).compactMap(\.payloadStringValue)
        lines.append(contentsOf: payloads.filter { !lines.contains($0) })
        return lines.joined(separator: "\n")
    }
}
