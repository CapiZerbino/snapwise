import AppKit

/// The status item: a command menu normally, a stop button with a timer while recording.
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        recordingStateChanged()
    }

    func rebuildMenu() {
        guard let statusItem, !RecordingManager.shared.isRecording else { return }
        statusItem.menu = makeMenu()
    }

    func recordingStateChanged() {
        guard let statusItem, let button = statusItem.button else { return }
        let manager = RecordingManager.shared
        if manager.isRecording {
            // Without a menu the click reaches `statusClicked`, so one click stops the recording.
            statusItem.menu = nil
            button.image = NSImage(systemSymbolName: manager.isPaused ? "pause.circle.fill" : "stop.circle.fill", accessibilityDescription: "Stop recording")
            button.contentTintColor = .systemRed
            button.title = " " + manager.elapsedText
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapwise")
            button.contentTintColor = nil
            button.title = ""
            statusItem.menu = makeMenu()
        }
    }

    @objc private func statusClicked() {
        guard RecordingManager.shared.isRecording, let statusItem else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true {
            let menu = NSMenu()
            menu.addItem(plain("Stop Recording", #selector(stopRecording)))
            menu.addItem(plain(RecordingManager.shared.isPaused ? "Resume" : "Pause", #selector(togglePause)))
            menu.addItem(plain("Discard Recording", #selector(discardRecording)))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            RecordingManager.shared.stop()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let groups: [[AppAction]] = [
            [.captureArea, .capturePreviousArea, .captureFullscreen, .captureWindow, .scrollingCapture, .selfTimer, .allInOne],
            [.recordVideo, .recordGIF],
            [.captureText, .convertFiles],
            [.openFile, .annotateClipboard, .pinClipboard, .openHistory, .restoreRecentlyClosed],
        ]
        for group in groups {
            group.forEach { menu.addItem(item(for: $0)) }
            menu.addItem(.separator())
        }
        let snapping = NSMenuItem(title: "Snap Window", action: nil, keyEquivalent: "")
        snapping.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
        let snapMenu = NSMenu()
        for (index, action) in AppAction.snapActions.enumerated() {
            // Separators between halves, quarters, sizes/thirds, display moves and edge moves.
            if [4, 8, 10, 15, 18].contains(index) { snapMenu.addItem(.separator()) }
            snapMenu.addItem(item(for: action))
        }
        snapMenu.addItem(.separator())
        snapMenu.addItem(plain("Snapping Settings…", #selector(openSnapping), symbol: "gearshape"))
        snapping.submenu = snapMenu
        menu.addItem(snapping)
        menu.addItem(.separator())
        let icons = item(for: .toggleDesktopIcons)
        icons.state = DesktopIconsHider.isHidden ? .on : .off
        menu.addItem(icons)
        let overlays = plain("Hide Overlays", #selector(toggleOverlays), symbol: "rectangle.on.rectangle.slash")
        overlays.state = QuickAccessManager.shared.isHidden ? .on : .off
        menu.addItem(overlays)
        if PinWindowController.hasLockedPins { menu.addItem(plain("Unlock Pinned Screenshots", #selector(unlockPins), symbol: "lock.open")) }
        menu.addItem(.separator())
        menu.addItem(plain("Customize Shortcuts…", #selector(openShortcuts), symbol: "keyboard"))
        menu.addItem(plain("Settings…", #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(plain("Quit Snapwise", #selector(quit), key: "q"))
        return menu
    }

    private func item(for action: AppAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
        if action == .restoreRecentlyClosed, !QuickAccessManager.shared.canRestore { item.action = nil }
        // Shown for reference; the global hotkey does the real work.
        if let hotkey = HotkeyManager.shared.hotkey(for: action), let key = hotkey.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = hotkey.cocoaModifiers
        }
        return item
    }

    private func plain(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = AppAction(rawValue: raw) else { return }
        // Let the menu finish closing so it is not part of the capture (and focus returns to the window to snap).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { CaptureCoordinator.shared.perform(action) }
    }

    @objc private func toggleOverlays() {
        QuickAccessManager.shared.isHidden.toggle()
        rebuildMenu()
    }

    @objc private func unlockPins() { PinWindowController.unlockAll() }
    @objc private func openSettings() { SettingsWindowController.show() }
    @objc private func openShortcuts() { SettingsWindowController.show(tab: .shortcuts) }
    @objc private func openSnapping() { SettingsWindowController.show(tab: .snapping) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func stopRecording() { RecordingManager.shared.stop() }
    @objc private func togglePause() { RecordingManager.shared.togglePause() }
    @objc private func discardRecording() { RecordingManager.shared.discard() }
}

/// Minimal main menu so standard key equivalents (⌘Z, ⌘C, ⌘S, ⌘W…) reach our windows even without a Dock icon.
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Quit Snapwise", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "Snapwise"))

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Save", action: Selector(("saveDocument:")), keyEquivalent: "s")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(file, title: "File"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, title: "Edit"))

        NSApp.mainMenu = main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
