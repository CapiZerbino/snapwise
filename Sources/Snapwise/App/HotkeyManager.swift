import AppKit
import Carbon.HIToolbox

/// Every user-triggerable command; shared by the menu, global hotkeys and the URL scheme.
enum AppAction: String, CaseIterable {
    case allInOne = "all-in-one"
    case captureArea = "capture-area"
    case capturePreviousArea = "capture-previous-area"
    case captureFullscreen = "capture-fullscreen"
    case captureWindow = "capture-window"
    case selfTimer = "self-timer"
    case scrollingCapture = "scrolling-capture"
    case recordVideo = "record-screen"
    case recordGIF = "record-gif"
    case captureText = "capture-text"
    case toggleDesktopIcons = "toggle-desktop-icons"
    case openHistory = "open-history"
    case restoreRecentlyClosed = "restore-recently-closed"
    case annotateClipboard = "annotate-clipboard"
    case pinClipboard = "pin-clipboard"
    case openFile = "open-file"
    // Window snapping; the part after `snap-` is a `SnapPosition` raw value.
    case snapLeftHalf = "snap-left-half"
    case snapRightHalf = "snap-right-half"
    case snapTopHalf = "snap-top-half"
    case snapBottomHalf = "snap-bottom-half"
    case snapTopLeft = "snap-top-left"
    case snapTopRight = "snap-top-right"
    case snapBottomLeft = "snap-bottom-left"
    case snapBottomRight = "snap-bottom-right"
    case snapMaximize = "snap-maximize"
    case snapCenter = "snap-center"
    case snapLeftThird = "snap-left-third"
    case snapCenterThird = "snap-center-third"
    case snapRightThird = "snap-right-third"
    case snapLeftTwoThirds = "snap-left-two-thirds"
    case snapRightTwoThirds = "snap-right-two-thirds"
    case snapNextDisplay = "snap-next-display"
    case snapPreviousDisplay = "snap-previous-display"
    case snapRestore = "snap-restore"
    case snapMoveLeft = "snap-move-left"
    case snapMoveRight = "snap-move-right"
    case snapMoveUp = "snap-move-up"
    case snapMoveDown = "snap-move-down"

    /// The window position this action snaps to, for the snapping actions.
    var snapPosition: SnapPosition? {
        rawValue.hasPrefix("snap-") ? SnapPosition(rawValue: String(rawValue.dropFirst(5))) : nil
    }

    static let snapActions: [AppAction] = allCases.filter { $0.snapPosition != nil }

    var title: String {
        if let snapPosition { return snapPosition.title }
        switch self {
        case .allInOne: return "All-In-One"
        case .captureArea: return "Capture Area"
        case .capturePreviousArea: return "Capture Previous Area"
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureWindow: return "Capture Window"
        case .selfTimer: return "Self-Timer"
        case .scrollingCapture: return "Scrolling Capture"
        case .recordVideo: return "Record Video"
        case .recordGIF: return "Record GIF"
        case .captureText: return "Capture Text (OCR)"
        case .toggleDesktopIcons: return "Hide Desktop Icons"
        case .openHistory: return "Capture History…"
        case .restoreRecentlyClosed: return "Restore Recently Closed"
        case .annotateClipboard: return "Annotate from Clipboard"
        case .pinClipboard: return "Pin from Clipboard"
        case .openFile: return "Open File…"
        default: return rawValue
        }
    }

    var symbol: String {
        if let snapPosition { return snapPosition.symbol }
        switch self {
        case .allInOne: return "rectangle.dashed.badge.record"
        case .captureArea: return "rectangle.dashed"
        case .capturePreviousArea: return "arrow.counterclockwise.square"
        case .captureFullscreen: return "desktopcomputer"
        case .captureWindow: return "macwindow"
        case .selfTimer: return "timer"
        case .scrollingCapture: return "arrow.up.and.down.square"
        case .recordVideo: return "video"
        case .recordGIF: return "photo.stack"
        case .captureText: return "text.viewfinder"
        case .toggleDesktopIcons: return "eye.slash"
        case .openHistory: return "clock.arrow.circlepath"
        case .restoreRecentlyClosed: return "arrow.uturn.backward.square"
        case .annotateClipboard: return "pencil.and.outline"
        case .pinClipboard: return "pin"
        case .openFile: return "folder"
        default: return "macwindow"
        }
    }

    /// Sections of the Shortcuts settings pane.
    static let groups: [(title: String, actions: [AppAction])] = [
        ("Screenshots", [.captureArea, .capturePreviousArea, .captureFullscreen, .captureWindow, .selfTimer, .scrollingCapture, .allInOne]),
        ("Screen Recording", [.recordVideo, .recordGIF]),
        ("Tools", [.captureText, .openFile, .annotateClipboard, .pinClipboard, .openHistory, .restoreRecentlyClosed, .toggleDesktopIcons]),
        ("Window Snapping", snapActions),
    ]

    var defaultHotkey: Hotkey? {
        let mods = UInt32(controlKey | shiftKey)
        // Snapping uses ⌃⌥ so it never collides with the capture shortcuts.
        let snap = UInt32(controlKey | optionKey)
        let snapKeys: [AppAction: (Int, UInt32)] = [
            .snapLeftHalf: (kVK_LeftArrow, snap), .snapRightHalf: (kVK_RightArrow, snap),
            .snapTopHalf: (kVK_UpArrow, snap), .snapBottomHalf: (kVK_DownArrow, snap),
            .snapTopLeft: (kVK_ANSI_U, snap), .snapTopRight: (kVK_ANSI_I, snap),
            .snapBottomLeft: (kVK_ANSI_J, snap), .snapBottomRight: (kVK_ANSI_K, snap),
            .snapMaximize: (kVK_Return, snap), .snapCenter: (kVK_ANSI_C, snap),
            .snapLeftThird: (kVK_ANSI_D, snap), .snapCenterThird: (kVK_ANSI_F, snap), .snapRightThird: (kVK_ANSI_G, snap),
            .snapLeftTwoThirds: (kVK_ANSI_E, snap), .snapRightTwoThirds: (kVK_ANSI_T, snap),
            .snapNextDisplay: (kVK_RightArrow, snap | UInt32(cmdKey)), .snapPreviousDisplay: (kVK_LeftArrow, snap | UInt32(cmdKey)),
            .snapRestore: (kVK_Delete, snap),
            .snapMoveLeft: (kVK_LeftArrow, snap | UInt32(shiftKey)), .snapMoveRight: (kVK_RightArrow, snap | UInt32(shiftKey)),
            .snapMoveUp: (kVK_UpArrow, snap | UInt32(shiftKey)), .snapMoveDown: (kVK_DownArrow, snap | UInt32(shiftKey)),
        ]
        if let (key, modifiers) = snapKeys[self] { return Hotkey(keyCode: UInt32(key), modifiers: modifiers) }
        switch self {
        case .allInOne: return Hotkey(keyCode: UInt32(kVK_ANSI_1), modifiers: mods)
        case .captureText: return Hotkey(keyCode: UInt32(kVK_ANSI_2), modifiers: mods)
        case .captureFullscreen: return Hotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: mods)
        case .captureArea: return Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: mods)
        case .captureWindow: return Hotkey(keyCode: UInt32(kVK_ANSI_5), modifiers: mods)
        case .scrollingCapture: return Hotkey(keyCode: UInt32(kVK_ANSI_6), modifiers: mods)
        case .recordVideo: return Hotkey(keyCode: UInt32(kVK_ANSI_7), modifiers: mods)
        case .recordGIF: return Hotkey(keyCode: UInt32(kVK_ANSI_8), modifiers: mods)
        default: return nil
        }
    }
}

struct Hotkey: Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        // A bare key would hijack normal typing system-wide.
        guard !flags.subtracting(.shift).isEmpty || Hotkey.functionKeys.contains(Int(event.keyCode)) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: Hotkey.carbon(from: flags))
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":").compactMap { UInt32($0) }
        guard parts.count == 2 else { return nil }
        self.init(keyCode: parts[0], modifiers: parts[1])
    }

    var stored: String { "\(keyCode):\(modifiers)" }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }

    var keyName: String { Hotkey.keyNames[Int(keyCode)] ?? "Key \(keyCode)" }

    var display: String { Hotkey.symbols(for: cocoaModifiers) + keyName }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    /// The character NSMenuItem needs to draw this shortcut next to a menu item.
    var menuKeyEquivalent: String? {
        if let index = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].firstIndex(of: Int(keyCode)) {
            return UnicodeScalar(NSF1FunctionKey + index).map { String(Character($0)) }
        }
        let special: [Int: Int] = [kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
                                   kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey]
        if let code = special[Int(keyCode)] { return UnicodeScalar(code).map { String(Character($0)) } }
        switch Int(keyCode) {
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Delete: return "\u{8}"
        case kVK_Escape: return "\u{1B}"
        default: return keyName.count == 1 ? keyName.lowercased() : nil
        }
    }

    static func carbon(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]

    static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]
}

/// Registers system-wide shortcuts through Carbon, which needs no accessibility permission.
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    /// Bumped after every (re)registration so settings rows refresh.
    @Published private(set) var revision = 0
    /// Shortcuts the system refused, typically because another app already owns them.
    private(set) var failed = Set<AppAction>()

    private var refs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: AppAction] = [:]
    private var handlerInstalled = false

    func hotkey(for action: AppAction) -> Hotkey? {
        guard let stored = UserDefaults.standard.string(forKey: "hotkey." + action.rawValue) else { return action.defaultHotkey }
        return Hotkey(stored: stored) // an empty string means the user cleared the shortcut
    }

    func setHotkey(_ hotkey: Hotkey?, for action: AppAction) {
        // A combination can only trigger one action: assigning it here takes it away from its previous owner.
        if let hotkey {
            for other in AppAction.allCases where other != action && self.hotkey(for: other) == hotkey { store(nil, for: other) }
        }
        store(hotkey, for: action)
        registerAll()
        MenuBarController.shared.rebuildMenu()
    }

    private func store(_ hotkey: Hotkey?, for action: AppAction) {
        UserDefaults.standard.set(hotkey?.stored ?? "", forKey: "hotkey." + action.rawValue)
    }

    func resetToDefaults() {
        AppAction.allCases.forEach { UserDefaults.standard.removeObject(forKey: "hotkey." + $0.rawValue) }
        registerAll()
        MenuBarController.shared.rebuildMenu()
    }

    /// The combinations macOS uses for its own screenshot tool; they only reach us once those are switched off in System Settings.
    func applySystemStylePreset() {
        let mods = UInt32(cmdKey | shiftKey)
        let preset: [AppAction: Int] = [.captureFullscreen: kVK_ANSI_3, .captureArea: kVK_ANSI_4, .allInOne: kVK_ANSI_5,
                                        .captureWindow: kVK_ANSI_6, .recordVideo: kVK_ANSI_7, .captureText: kVK_ANSI_2]
        for (action, key) in preset {
            let hotkey = Hotkey(keyCode: UInt32(key), modifiers: mods)
            for other in AppAction.allCases where preset[other] == nil && self.hotkey(for: other) == hotkey { store(nil, for: other) }
            store(hotkey, for: action)
        }
        registerAll()
        MenuBarController.shared.rebuildMenu()
    }

    /// Releases every hotkey, e.g. while the user records a new shortcut.
    func suspend() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actionsByID = [:]
        failed = []
    }

    func registerAll() {
        installHandlerIfNeeded()
        suspend()
        for (index, action) in AppAction.allCases.enumerated() {
            // Snapping shortcuts are only claimed while the feature is on, leaving ⌃⌥-arrows to other apps otherwise.
            if action.snapPosition != nil, !Prefs.shared.snapEnabled { continue }
            guard let hotkey = hotkey(for: action) else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4C4D5348), id: id) // 'LMSH'
            if RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
                actionsByID[id] = action
            } else {
                failed.insert(action)
            }
        }
        revision += 1
    }

    fileprivate func fire(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        DispatchQueue.main.async { CaptureCoordinator.shared.perform(action) }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotkeyManager.shared.fire(id: hotKeyID.id)
            return noErr
        }, 1, &spec, nil, nil)
    }
}
