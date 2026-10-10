import AppKit
import ScreenCaptureKit

enum RecordTarget {
    case area(CGRect, NSScreen)
    case window(WindowInfo)
    case fullscreen(NSScreen)
}

/// Drives one recording at a time: countdown, overlays, capture, and hand-off to history.
final class RecordingManager {
    static let shared = RecordingManager()

    /// True from the countdown until the file is finalized.
    private(set) var isActive = false
    private(set) var isRecording = false
    private(set) var isPaused = false

    private var recorder: ScreenRecorder?
    private var gif = false
    private var pixelSize = CGSize.zero
    private var scale: CGFloat = 1
    private var startDate = Date()
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var ticker: Timer?
    private var border: RecordingBorder?
    private var clicks: ClickTracker?
    private var keystrokes: KeystrokeOverlay?
    private var camera: CameraOverlay?
    private var hidIcons = false
    private let prefs = Prefs.shared
    /// Called once after the current recording has been finalized or abandoned.
    var onFinished: (() -> Void)?

    var elapsed: TimeInterval {
        guard isRecording else { return 0 }
        return (pausedAt ?? Date()).timeIntervalSince(startDate) - pausedTotal
    }

    var elapsedText: String {
        let seconds = Int(elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func start(target: RecordTarget, gif: Bool) {
        guard !isActive, Permissions.ensureScreenRecording() else { return }
        let (area, screen) = geometry(of: target)
        guard area.width >= 32, area.height >= 32 else { return Toast.show("The area is too small to record") }
        isActive = true
        self.gif = gif

        if prefs.recHideDesktopIcons, !DesktopIconsHider.isHidden {
            DesktopIconsHider.setHidden(true)
            hidIcons = true
        }
        if case .area = target { border = RecordingBorder(area: area) }
        // Overlays that must appear in the video have to exist before the capture filter is created.
        if prefs.recCamera, !gif { camera = CameraOverlay(area: area) }
        if prefs.recShowKeystrokes { keystrokes = KeystrokeOverlay(area: area) }
        clicks = ClickTracker(area: area, screen: screen) { [weak self] in self?.isRecording == true ? self?.elapsed ?? -1 : -1 }
        MenuBarController.shared.recordingStateChanged()

        CountdownHUD.run(seconds: prefs.recCountdown, on: screen) { [weak self] completed in
            guard let self else { return }
            if completed { self.begin(target: target, area: area, screen: screen) } else { self.reset() }
        }
    }

    private func geometry(of target: RecordTarget) -> (CGRect, NSScreen) {
        switch target {
        case .area(let rect, let screen): return (rect, screen)
        case .fullscreen(let screen): return (screen.frame, screen)
        case .window(let info):
            let screen = NSScreen.screens.first { $0.frame.intersects(info.frame) } ?? .underMouse
            return (info.frame.intersection(screen.frame), screen)
        }
    }

    private func begin(target: RecordTarget, area: CGRect, screen: NSScreen) {
        Task { @MainActor in
            do {
                let content = try await ScreenCapture.content()
                let filter: SCContentFilter
                var sourceRect: CGRect?
                switch target {
                case .window(let info):
                    // Composite the window with our click/keystroke/camera overlays; a window-only filter would drop them.
                    guard let window = content.windows.first(where: { $0.windowID == info.id }),
                          let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { throw CaptureError.noWindow }
                    let pid = getpid()
                    let overlays = content.windows.filter {
                        $0.owningApplication?.processID == pid && CaptureVisibility.isIncluded($0.windowID, recording: true)
                    }
                    filter = SCContentFilter(display: display, including: [window] + overlays)
                    sourceRect = screen.localTopLeft(area)
                case .area(let rect, _):
                    filter = try ScreenCapture.displayFilter(screen: screen, content: content, forRecording: true)
                    sourceRect = screen.localTopLeft(rect)
                case .fullscreen:
                    filter = try ScreenCapture.displayFilter(screen: screen, content: content, forRecording: true)
                }

                scale = prefs.recRetina ? screen.backingScaleFactor : 1
                pixelSize = RecordingManager.encodableSize(CGSize(width: area.width * scale, height: area.height * scale))
                let fps = gif ? max(prefs.gifFPS, 10) : prefs.recFPS
                let bitsPerPixel: Double = ["low": 0.05, "medium": 0.1, "high": 0.18][prefs.recQuality] ?? 0.1
                let settings = ScreenRecorder.Settings(
                    pixelSize: pixelSize, sourceRect: sourceRect, fps: fps,
                    bitrate: Int(Double(pixelSize.width * pixelSize.height) * Double(fps) * bitsPerPixel),
                    showCursor: prefs.recShowCursor, systemAudio: prefs.recSystemAudio && !gif, microphone: prefs.recMicrophone && !gif)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapwise-\(UUID().uuidString).mp4")
                let recorder = try ScreenRecorder(filter: filter, settings: settings, url: url)
                recorder.onError = { [weak self] error in
                    DispatchQueue.main.async {
                        Toast.show("Recording stopped: \(error.localizedDescription)")
                        self?.stop()
                    }
                }
                do {
                    try await recorder.start()
                } catch {
                    recorder.cancel()
                    throw error
                }
                self.recorder = recorder
                startDate = Date()
                pausedTotal = 0
                pausedAt = nil
                isRecording = true
                isPaused = false
                Log.app.notice("Recording started: \(Int(self.pixelSize.width))x\(Int(self.pixelSize.height)) px, gif=\(self.gif)")
                ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in MenuBarController.shared.recordingStateChanged() }
                MenuBarController.shared.recordingStateChanged()
            } catch {
                Log.app.error("Recording failed to start: \(String(describing: error), privacy: .public)")
                Toast.show("Could not start recording: \(error.localizedDescription)")
                reset()
            }
        }
    }

    /// H.264 needs even dimensions and tops out around 4K, so larger areas are scaled down.
    static func encodableSize(_ size: CGSize, maxWidth: CGFloat = 3840, maxHeight: CGFloat = 2160) -> CGSize {
        let k = min(1, maxWidth / size.width, maxHeight / size.height)
        func even(_ v: CGFloat) -> CGFloat { max(2, (v * k / 2).rounded(.down) * 2) }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        if isPaused {
            pausedAt = Date()
        } else if let pausedAt {
            pausedTotal += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        recorder?.setPaused(isPaused)
        MenuBarController.shared.recordingStateChanged()
    }

    /// Stops and keeps the recording; during the countdown it cancels instead.
    func stop() {
        if isActive, !isRecording, recorder == nil {
            CountdownHUD.cancel()
        } else {
            finish(keep: true)
        }
    }
    func discard() { finish(keep: false) }

    private func finish(keep: Bool) {
        guard isRecording, let recorder else { return }
        let recordedClicks = clicks?.events ?? []
        let gif = gif, pixelSize = pixelSize, scale = scale
        isRecording = false
        teardownOverlays()
        MenuBarController.shared.recordingStateChanged()

        Task { @MainActor in
            defer { reset() }
            guard let url = await recorder.stop() else {
                Log.app.error("Recording produced no file: \(String(describing: recorder.failure), privacy: .public)")
                if keep { Toast.show("Recording failed: \(recorder.failure?.localizedDescription ?? "nothing was captured")") }
                return
            }
            guard keep else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            var finalURL = url
            var gif = gif
            if gif {
                Toast.show("Converting to GIF…", duration: 30)
                let gifURL = url.deletingPathExtension().appendingPathExtension("gif")
                do {
                    try await GIFExporter.export(videoURL: url, to: gifURL, fps: prefs.gifFPS, maxWidth: prefs.gifMaxWidth)
                    try? FileManager.default.removeItem(at: url)
                    finalURL = gifURL
                } catch {
                    // Keep the footage: fall back to the MP4 it was converted from.
                    Toast.show("GIF export failed, kept the video: \(error.localizedDescription)")
                    gif = false
                }
            }
            Log.app.notice("Recording finished: \(finalURL.pathExtension, privacy: .public)")
            guard let item = HistoryStore.shared.add(fileAt: finalURL, kind: gif ? .gif : .video, pixelSize: pixelSize, scale: scale) else {
                return Toast.show("Could not store the recording")
            }
            if !gif, !recordedClicks.isEmpty, let data = try? JSONEncoder().encode(recordedClicks) {
                try? data.write(to: item.clicksURL)
            }
            if finalURL.pathExtension == "gif" || !self.gif { Toast.show(gif ? "GIF ready" : "Recording ready") }
            if prefs.afterCaptureSave { Output.save(fileAt: item.url, kind: item.kind.label) }
            QuickAccessManager.shared.show(item)
        }
    }

    private func teardownOverlays() {
        ticker?.invalidate()
        ticker = nil
        border?.close()
        border = nil
        clicks?.stop()
        clicks = nil
        keystrokes?.stop()
        keystrokes = nil
        camera?.stop()
        camera = nil
        if hidIcons {
            hidIcons = false
            DesktopIconsHider.setHidden(false)
        }
    }

    private func reset() {
        teardownOverlays()
        recorder = nil
        isActive = false
        isRecording = false
        isPaused = false
        MenuBarController.shared.recordingStateChanged()
        let finished = onFinished
        onFinished = nil
        finished?()
    }
}
