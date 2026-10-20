import AppKit
import UniformTypeIdentifiers

/// Routes every command to its capture flow and applies the after-capture preferences.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private enum Intent {
        case screenshot, timer, ocr, scrolling, allInOne
        case record(gif: Bool)
    }

    private let prefs = Prefs.shared
    /// True when we hid the desktop icons only for the duration of one capture.
    private var iconsHiddenForCapture = false
    /// Covers the async gap between a command and its overlay appearing, so a double press cannot start two.
    private var preparingSelection = false

    func perform(_ action: AppAction) {
        if let position = action.snapPosition { return SnapManager.shared.snap(position) }
        switch action {
        case .allInOne: select(.allInOne, intent: .allInOne)
        case .captureArea: select(.area, intent: .screenshot)
        case .captureWindow: select(.window, intent: .screenshot)
        case .selfTimer: select(.area, intent: .timer)
        case .scrollingCapture: select(.area, intent: .scrolling)
        case .captureText: select(.area, intent: .ocr)
        case .captureFullscreen: guardPermission { self.capture(screen: .underMouse, rect: nil) }
        case .capturePreviousArea: capturePreviousArea()
        case .recordVideo: toggleRecording(gif: false)
        case .recordGIF: toggleRecording(gif: true)
        case .toggleDesktopIcons:
            DesktopIconsHider.toggle()
            MenuBarController.shared.rebuildMenu()
        case .openHistory: HistoryWindowController.show()
        case .restoreRecentlyClosed: QuickAccessManager.shared.restoreRecentlyClosed()
        case .annotateClipboard:
            if let item = itemFromClipboard() { EditorWindowController.open(item: item) }
        case .pinClipboard:
            if let item = itemFromClipboard(), let image = item.cgImage { PinWindowController.pin(image: image, scale: item.scale) }
        case .openFile: chooseFile()
        case .convertFiles: FileDragMonitor.chooseFiles()
        default: break // snapping actions returned above
        }
    }

    /// Runs an area command on a fixed rect (AppKit global coordinates) without showing the selection overlay.
    /// Backs the `x`/`y`/`width`/`height` parameters of the URL scheme.
    func perform(_ action: AppAction, in rect: CGRect) {
        guard Permissions.ensureScreenRecording() else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(rect.center) } ?? .underMouse
        let area = rect.intersection(screen.frame).integral
        guard area.width >= 2, area.height >= 2 else { return Toast.show("The requested area is off screen") }
        let intent: Intent
        switch action {
        case .captureText: intent = .ocr
        case .scrollingCapture: intent = .scrolling
        case .recordVideo: intent = .record(gif: false)
        case .recordGIF: intent = .record(gif: true)
        default: intent = .screenshot
        }
        route(rect: area, screen: screen, action: self.action(for: intent, chosen: .screenshot), frozen: nil,
              intent: intent, recordTarget: .area(area, screen))
    }

    // MARK: - Selection

    private func guardPermission(_ body: @escaping () -> Void) {
        guard Permissions.ensureScreenRecording() else { return }
        body()
    }

    private func toggleRecording(gif: Bool) {
        if RecordingManager.shared.isActive {
            RecordingManager.shared.stop()
        } else {
            select(.record, intent: .record(gif: gif))
        }
    }

    private func select(_ mode: SelectionMode, intent: Intent) {
        guard !SelectionOverlay.isActive, !preparingSelection, Permissions.ensureScreenRecording() else { return }
        preparingSelection = true
        Task { @MainActor in
            defer { preparingSelection = false }
            if prefs.hideDesktopIconsOnCapture, !DesktopIconsHider.isHidden {
                DesktopIconsHider.setHidden(true)
                iconsHiddenForCapture = true
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            var snapshots: [CGDirectDisplayID: CGImage] = [:]
            // Snapshots only feed the frozen backdrop and the magnifier.
            if prefs.freezeScreen || prefs.showMagnifier, let content = try? await ScreenCapture.content() {
                for screen in NSScreen.screens {
                    snapshots[screen.displayID] = try? await ScreenCapture.image(screen: screen, content: content)
                }
            }
            var recordGIF = false
            if case .record(let gif) = intent { recordGIF = gif }
            SelectionOverlay.begin(mode: mode, recordGIF: recordGIF, snapshots: snapshots) { [weak self] result in
                self?.handle(result, intent: intent)
            }
        }
    }

    private func handle(_ result: SelectionResult, intent: Intent) {
        switch result {
        case .cancelled:
            endCapture()
        case .fullscreen(let screen):
            route(rect: screen.frame, screen: screen, action: action(for: intent, chosen: .screenshot), frozen: nil,
                  intent: intent, recordTarget: .fullscreen(screen))
        case .window(let info):
            let screen = NSScreen.screens.first { $0.frame.intersects(info.frame) } ?? .underMouse
            switch action(for: intent, chosen: .screenshot) {
            case .screenshot:
                afterTimer(intent, screen: screen) { self.captureWindow(info, screen: screen) }
            default:
                route(rect: info.frame.intersection(screen.frame), screen: screen, action: action(for: intent, chosen: .screenshot),
                      frozen: nil, intent: intent, recordTarget: .window(info))
            }
        case .area(let rect, let screen, let chosen, let frozen):
            route(rect: rect, screen: screen, action: action(for: intent, chosen: chosen), frozen: frozen,
                  intent: intent, recordTarget: .area(rect, screen))
        }
    }

    private func action(for intent: Intent, chosen: AreaAction) -> AreaAction {
        switch intent {
        case .screenshot, .timer: return .screenshot
        case .ocr: return .ocr
        case .scrolling: return .scrolling
        case .record(let gif):
            // The recording bar can switch between video and GIF after the shortcut was pressed.
            if chosen == .video || chosen == .gif { return chosen }
            return gif ? .gif : .video
        case .allInOne: return chosen
        }
    }

    private func route(rect: CGRect, screen: NSScreen, action: AreaAction, frozen: CGImage?, intent: Intent, recordTarget: RecordTarget) {
        switch action {
        case .screenshot:
            prefs.previousArea = NSStringFromRect(rect)
            prefs.previousAreaDisplay = Int(screen.displayID)
            if let frozen, !isTimer(intent) {
                deliver(frozen, scale: screen.backingScaleFactor)
            } else {
                afterTimer(intent, screen: screen) { self.capture(screen: screen, rect: rect) }
            }
        case .ocr:
            Task { @MainActor in
                let image: CGImage?
                if let frozen { image = frozen } else { image = try? await ScreenCapture.image(screen: screen, rect: rect) }
                self.endCapture()
                guard let image else {
                    Log.app.error("OCR: capturing the area failed")
                    return Toast.show("Capture failed")
                }
                self.recognizeText(in: image)
            }
        case .scrolling:
            ScrollingCaptureSession.start(rect: rect, screen: screen) { [weak self] image in
                guard let self else { return }
                if let image { self.deliver(image, scale: screen.backingScaleFactor) } else { self.endCapture() }
            }
        case .video, .gif:
            endCapture()
            RecordingManager.shared.start(target: recordTarget, gif: action == .gif)
        }
    }

    private func isTimer(_ intent: Intent) -> Bool {
        if case .timer = intent { return true }
        return false
    }

    private func afterTimer(_ intent: Intent, screen: NSScreen, _ body: @escaping () -> Void) {
        guard isTimer(intent) else { return body() }
        CountdownHUD.run(seconds: prefs.timerSeconds, on: screen) { [weak self] completed in
            if completed { body() } else { self?.endCapture() }
        }
    }

    // MARK: - Capture

    private func capturePreviousArea() {
        let rect = NSRectFromString(prefs.previousArea)
        guard rect.width > 1, let screen = NSScreen.with(displayID: CGDirectDisplayID(prefs.previousAreaDisplay)) else {
            return Toast.show("No previous area yet")
        }
        guardPermission { self.capture(screen: screen, rect: rect) }
    }

    private func capture(screen: NSScreen, rect: CGRect?) {
        Task { @MainActor in
            do {
                let image = try await ScreenCapture.image(screen: screen, rect: rect, showCursor: prefs.captureCursor)
                deliver(image, scale: screen.backingScaleFactor)
            } catch {
                endCapture()
                Log.app.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                Toast.show("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    private func captureWindow(_ info: WindowInfo, screen: NSScreen) {
        Task { @MainActor in
            do {
                let shot = try await ScreenCapture.windowImage(id: info.id)
                deliver(WindowBackgroundComposer.compose(window: shot.image, scale: shot.scale, screen: screen), scale: shot.scale)
            } catch {
                endCapture()
                Toast.show("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    private func recognizeText(in image: CGImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = TextRecognizer.recognize(image)
            Log.app.notice("OCR: \(image.width)x\(image.height) px -> \(text.count) characters")
            DispatchQueue.main.async {
                guard !text.isEmpty else { return Toast.show("No text found") }
                Output.copy(text: text)
                let lines = text.components(separatedBy: "\n").count
                Output.playShutter()
                Toast.show("✓ Text copied to clipboard — \(text.count) characters, \(lines) line\(lines == 1 ? "" : "s")", detail: text, duration: 4)
            }
        }
    }

    private func endCapture() {
        if iconsHiddenForCapture {
            iconsHiddenForCapture = false
            DesktopIconsHider.setHidden(false)
        }
    }

    /// Final step of every screenshot flow: store it and run the user's after-capture actions.
    func deliver(_ captured: CGImage, scale captureScale: CGFloat) {
        endCapture()
        var image = captured
        var scale = captureScale
        if prefs.downscaleRetina, scale > 1,
           let small = image.resized(to: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)) {
            image = small
            scale = 1
        }
        Output.playShutter()
        Log.app.notice("Screenshot delivered: \(image.width)x\(image.height) px")
        guard let item = HistoryStore.shared.add(image: image, scale: scale) else { return Toast.show("Could not store the capture") }
        if prefs.afterCaptureCopy { Output.copy(image: image, scale: scale) }
        if prefs.afterCaptureSave, let url = Output.save(image: image, scale: scale) { Toast.show("Saved to \(url.lastPathComponent)") }
        if prefs.afterCaptureShowOverlay { QuickAccessManager.shared.show(item) }
        if prefs.afterCaptureAnnotate { EditorWindowController.open(item: item) }
        if prefs.afterCapturePin { PinWindowController.pin(image: image, scale: scale) }
    }

    // MARK: - External images

    private func itemFromClipboard() -> CaptureItem? {
        guard let image = NSImage(pasteboard: .general)?.cgImage else {
            Toast.show("No image on the clipboard")
            return nil
        }
        return HistoryStore.shared.add(image: image, scale: 1)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie] + ProjectFile.readableExtensions.compactMap { UTType(filenameExtension: $0) }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(fileURL: url)
    }

    /// Opens an image, a project file or a video in the matching editor.
    func open(fileURL url: URL, pin: Bool = false) {
        if ProjectFile.readableExtensions.contains(url.pathExtension.lowercased()) {
            EditorWindowController.open(projectAt: url)
            return
        }
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) {
            VideoEditorWindowController.open(url: url, clicksURL: nil)
            return
        }
        guard let image = NSImage(contentsOf: url)?.cgImage, let item = HistoryStore.shared.add(image: image, scale: 1) else {
            return Toast.show("Could not open \(url.lastPathComponent)")
        }
        if pin { PinWindowController.pin(image: image, scale: 1) } else { EditorWindowController.open(item: item) }
    }
}
