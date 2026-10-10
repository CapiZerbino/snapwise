import AppKit
import Combine

/// UserDefaults-backed property that notifies the enclosing ObservableObject,
/// so SwiftUI settings can bind with `$prefs.someKey` while AppKit code reads plain values.
@propertyWrapper
struct Pref<T> {
    let key: String
    let def: T

    init(_ key: String, _ def: T) {
        self.key = key
        self.def = def
    }

    @available(*, unavailable)
    var wrappedValue: T {
        get { fatalError("Pref is only usable inside a class") }
        set { fatalError("Pref is only usable inside a class") }
    }

    static subscript<O: ObservableObject>(
        _enclosingInstance object: O,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<O, T>,
        storage storageKeyPath: ReferenceWritableKeyPath<O, Pref<T>>
    ) -> T where O.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let pref = object[keyPath: storageKeyPath]
            return UserDefaults.standard.object(forKey: pref.key) as? T ?? pref.def
        }
        set {
            object.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: object[keyPath: storageKeyPath].key)
        }
    }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()

    // General
    @Pref("playSounds", true) var playSounds: Bool
    @Pref("afterCaptureShowOverlay", true) var afterCaptureShowOverlay: Bool
    @Pref("afterCaptureCopy", true) var afterCaptureCopy: Bool
    @Pref("afterCaptureSave", false) var afterCaptureSave: Bool
    @Pref("afterCaptureAnnotate", false) var afterCaptureAnnotate: Bool
    @Pref("afterCapturePin", false) var afterCapturePin: Bool
    @Pref("saveFolder", ("~/Desktop" as NSString).expandingTildeInPath) var saveFolder: String
    @Pref("filenamePattern", "Snapwise {date} at {time}") var filenamePattern: String

    // Screenshots
    @Pref("imageFormat", "png") var imageFormat: String
    @Pref("jpegQuality", 0.9) var jpegQuality: Double
    @Pref("downscaleRetina", false) var downscaleRetina: Bool
    @Pref("captureCursor", false) var captureCursor: Bool
    @Pref("showCrosshair", true) var showCrosshair: Bool
    @Pref("showMagnifier", true) var showMagnifier: Bool
    @Pref("freezeScreen", false) var freezeScreen: Bool
    @Pref("hideDesktopIconsOnCapture", false) var hideDesktopIconsOnCapture: Bool
    @Pref("timerSeconds", 5) var timerSeconds: Int
    @Pref("rememberAllInOne", true) var rememberAllInOne: Bool

    // Window screenshots: transparent | wallpaper | solid | gradient
    @Pref("windowBackground", "transparent") var windowBackground: String
    @Pref("windowPadding", 48.0) var windowPadding: Double
    @Pref("windowShadow", true) var windowShadow: Bool
    @Pref("windowSolidColor", "#DDE3EA") var windowSolidColor: String
    @Pref("windowGradientIndex", 0) var windowGradientIndex: Int

    // Recording
    @Pref("recFPS", 30) var recFPS: Int
    @Pref("recQuality", "high") var recQuality: String
    @Pref("recRetina", true) var recRetina: Bool
    @Pref("recShowCursor", true) var recShowCursor: Bool
    @Pref("recSystemAudio", false) var recSystemAudio: Bool
    @Pref("recMicrophone", false) var recMicrophone: Bool
    @Pref("recCountdown", 3) var recCountdown: Int
    @Pref("recHideDesktopIcons", false) var recHideDesktopIcons: Bool
    @Pref("recHighlightClicks", false) var recHighlightClicks: Bool
    @Pref("clickColor", "#FFCC00") var clickColor: String
    @Pref("clickSize", 40.0) var clickSize: Double
    @Pref("clickFilled", false) var clickFilled: Bool
    @Pref("clickAnimated", true) var clickAnimated: Bool
    @Pref("recShowKeystrokes", false) var recShowKeystrokes: Bool
    @Pref("keystrokeCommandsOnly", false) var keystrokeCommandsOnly: Bool
    @Pref("keystrokePosition", "bottom") var keystrokePosition: String
    @Pref("keystrokeLight", false) var keystrokeLight: Bool
    @Pref("keystrokeSize", 22.0) var keystrokeSize: Double
    @Pref("recCamera", false) var recCamera: Bool
    @Pref("cameraSize", 180.0) var cameraSize: Double
    @Pref("cameraShape", "circle") var cameraShape: String
    @Pref("cameraPosition", "bottomRight") var cameraPosition: String
    @Pref("gifFPS", 15) var gifFPS: Int
    @Pref("gifMaxWidth", 960) var gifMaxWidth: Int

    // Quick access overlay
    @Pref("overlayOnLeft", true) var overlayOnLeft: Bool
    @Pref("overlaySize", 220.0) var overlaySize: Double
    @Pref("overlayAutoClose", false) var overlayAutoClose: Bool
    @Pref("overlayAutoCloseSeconds", 30) var overlayAutoCloseSeconds: Int
    @Pref("overlayCloseAfterDrag", true) var overlayCloseAfterDrag: Bool

    // Window snapping
    @Pref("snapEnabled", true) var snapEnabled: Bool
    @Pref("snapDrag", true) var snapDrag: Bool
    @Pref("snapGap", 0.0) var snapGap: Double
    @Pref("snapRestoreOnDrag", true) var snapRestoreOnDrag: Bool
    @Pref("snapCycleSizes", true) var snapCycleSizes: Bool
    @Pref("snapHaptics", true) var snapHaptics: Bool
    @Pref("snapNativeTilingAsked", false) var snapNativeTilingAsked: Bool
    @Pref("snapTitlebarButtons", true) var snapTitlebarButtons: Bool
    @Pref("snapMoveModifier", "off") var snapMoveModifier: String
    @Pref("snapResizeModifier", "off") var snapResizeModifier: String
    /// Comma-separated bundle identifiers that snapping leaves alone.
    @Pref("snapExcluded", "") var snapExcluded: String
    @Pref("customSnapAreas", Data()) var customSnapAreas: Data

    // History
    @Pref("historyRetentionDays", 30) var historyRetentionDays: Int

    // Remembered state
    @Pref("previousArea", "") var previousArea: String
    @Pref("previousAreaDisplay", 0) var previousAreaDisplay: Int
    @Pref("allInOneArea", "") var allInOneArea: String
    @Pref("customPalette", [String]()) var customPalette: [String]
    @Pref("backgroundPresets", Data()) var backgroundPresets: Data

    var saveFolderURL: URL { URL(fileURLWithPath: (saveFolder as NSString).expandingTildeInPath, isDirectory: true) }
}

extension NSColor {
    /// Parses `#RRGGBB` or `#RRGGBBAA`.
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count <= 6 { v = (v << 8) | 0xFF }
        self.init(srgbRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                  blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)), Int(round(c.alphaComponent * 255)))
    }
}
