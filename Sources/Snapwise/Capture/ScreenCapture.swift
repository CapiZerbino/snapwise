import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay, noWindow, noPermission

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "The display is no longer available."
        case .noWindow: return "The window is no longer available."
        case .noPermission: return "Screen Recording permission is required."
        }
    }
}

/// Our own windows are hidden from captures unless registered here
/// (e.g. the desktop-icon cover must stay visible, click highlights only matter in recordings).
enum CaptureVisibility {
    private static var always = Set<Int>()
    private static var recordingOnly = Set<Int>()

    static func include(_ window: NSWindow, recordingOnly rec: Bool = false) {
        if rec { recordingOnly.insert(window.windowNumber) } else { always.insert(window.windowNumber) }
    }

    static func remove(_ window: NSWindow) {
        always.remove(window.windowNumber)
        recordingOnly.remove(window.windowNumber)
    }

    static func isIncluded(_ id: CGWindowID, recording: Bool) -> Bool {
        always.contains(Int(id)) || (recording && recordingOnly.contains(Int(id)))
    }
}

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func displayFilter(screen: NSScreen, content: SCShareableContent, forRecording: Bool) throws -> SCContentFilter {
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { throw CaptureError.noDisplay }
        let pid = getpid()
        guard let ownApp = content.applications.first(where: { $0.processID == pid }) else {
            return SCContentFilter(display: display, excludingWindows: [])
        }
        // Excluding the whole app also hides windows we open later (toasts, overlay cards) from a running recording.
        let visible = content.windows.filter {
            $0.owningApplication?.processID == pid && CaptureVisibility.isIncluded($0.windowID, recording: forRecording)
        }
        return SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: visible)
    }

    /// Captures a display, or the part of it given by `rect` (AppKit global coordinates).
    /// Pass `content` when capturing several displays in a row to avoid re-querying the window server.
    static func image(screen: NSScreen, rect: CGRect? = nil, showCursor: Bool = false, content shared: SCShareableContent? = nil) async throws -> CGImage {
        let available: SCShareableContent
        if let shared { available = shared } else { available = try await content() }
        let filter = try displayFilter(screen: screen, content: available, forRecording: false)
        let scale = screen.backingScaleFactor
        let area = (rect ?? screen.frame).intersection(screen.frame)
        guard !area.isEmpty else { throw CaptureError.noDisplay }
        let config = SCStreamConfiguration()
        config.sourceRect = screen.localTopLeft(area)
        config.width = Int((area.width * scale).rounded())
        config.height = Int((area.height * scale).rounded())
        config.showsCursor = showCursor
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Captures a single window without its shadow, on a transparent background.
    static func windowImage(id: CGWindowID) async throws -> (image: CGImage, scale: CGFloat) {
        guard let window = try await content().windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = false
        config.backgroundColor = .clear
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }
}

struct WindowInfo {
    let id: CGWindowID
    /// AppKit global coordinates.
    let frame: CGRect
    let title: String
    let app: String
}

enum WindowList {
    /// Normal-layer windows of other apps, front to back.
    static func onScreen() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let pid = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != pid,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 40, bounds.height > 40 else { return nil }
            return WindowInfo(id: id, frame: Geo.flipGlobal(bounds),
                              title: info[kCGWindowName as String] as? String ?? "",
                              app: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}
