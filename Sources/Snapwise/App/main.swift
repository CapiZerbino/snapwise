import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Unit tests host inside the app; skip prompts and global state changes there.
    static let isRunningTests = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        MenuBarController.shared.install()
        guard !AppDelegate.isRunningTests else { return }
        // Two copies would both grab the hotkeys and answer URL commands, one of them possibly an outdated build.
        let me = NSRunningApplication.current
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") where other != me {
            Log.app.notice("Quitting another running copy at \(other.bundleURL?.path ?? "?", privacy: .public)")
            other.terminate()
        }
        HotkeyManager.shared.registerAll()
        SnapController.shared.refresh()
        HistoryStore.shared.purgeExpired()
        if !ScreenCapture.hasPermission { _ = Permissions.ensureScreenRecording() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(URLSchemeHandler.handle)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Quitting mid-recording finalizes and keeps the file instead of losing it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard RecordingManager.shared.isRecording else { return .terminateNow }
        RecordingManager.shared.onFinished = { NSApp.reply(toApplicationShouldTerminate: true) }
        RecordingManager.shared.stop()
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopIconsHider.setHidden(false)
    }
}

/// `snapwise://<action>[?filepath=…]` — the action names match `AppAction` raw values.
enum URLSchemeHandler {
    static func handle(_ url: URL) {
        if url.isFileURL { return CaptureCoordinator.shared.open(fileURL: url) }
        // `lumshot` is the app's former name; old links and scripts keep working.
        guard url.scheme == "snapwise" || url.scheme == "lumshot", let command = url.host else { return }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "filepath" }?.value
        let file = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        #if DEBUG
        if DebugAutomation.handle(command: command, url: url) { return }
        #endif
        // Optional fixed area, measured from the lower-left corner of the main display (same convention as CleanShot's API).
        let numbers = ["x", "y", "width", "height"].compactMap { name in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value.flatMap(Double.init)
        }
        if numbers.count == 4, let action = AppAction(rawValue: command),
           [.captureArea, .captureText, .scrollingCapture, .recordVideo, .recordGIF].contains(action) {
            return CaptureCoordinator.shared.perform(action, in: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
        }
        switch command {
        case "open-annotate":
            if let file { CaptureCoordinator.shared.open(fileURL: file) } else { CaptureCoordinator.shared.perform(.openFile) }
        case "pin":
            if let file { CaptureCoordinator.shared.open(fileURL: file, pin: true) } else { CaptureCoordinator.shared.perform(.pinClipboard) }
        case "open-settings":
            SettingsWindowController.show()
        case "hide-desktop-icons", "show-desktop-icons":
            DesktopIconsHider.setHidden(command == "hide-desktop-icons")
            MenuBarController.shared.rebuildMenu()
        default:
            if let action = AppAction(rawValue: command) { CaptureCoordinator.shared.perform(action) }
        }
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
