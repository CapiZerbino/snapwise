import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, shortcuts, screenshots, recording, overlay, snapping, advanced

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .screenshots: return "Screenshots"
        case .recording: return "Recording"
        case .overlay: return "Quick Access"
        case .snapping: return "Snapping"
        case .advanced: return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .screenshots: return "camera.viewfinder"
        case .recording: return "video"
        case .overlay: return "rectangle.on.rectangle"
        case .snapping: return "rectangle.split.2x1"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

enum SettingsWindowController {
    private static var window: NSWindow?

    static func show(tab: SettingsTab? = nil) {
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab") }
        if window == nil {
            window = WindowFactory.make(title: "Snapwise Settings", size: CGSize(width: 640, height: 600), resizable: false) { SettingsView() }
        }
        if let window { WindowFactory.present(window) }
    }
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var selected = SettingsTab.general.rawValue

    private var tab: SettingsTab { SettingsTab(rawValue: selected) ?? .general }

    var body: some View {
        VStack(spacing: 0) {
            // A hand-built tab strip: a TabView in a plain window collapses its tabs into an overflow button.
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { item in
                    Button { selected = item.rawValue } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 19)).frame(height: 22)
                            Text(item.title).font(.system(size: 11))
                        }
                        .frame(width: 82, height: 52)
                        .foregroundStyle(tab == item ? Color.accentColor : Color.secondary)
                        .background(tab == item ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            Divider()
            Group {
                switch tab {
                case .general: GeneralSettings()
                case .shortcuts: ShortcutSettings()
                case .screenshots: ScreenshotSettings()
                case .recording: RecordingSettings()
                case .overlay: OverlaySettings()
                case .snapping: SnappingSettings()
                case .advanced: AdvancedSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 600)
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        Toast.show("Could not change login item: \(error.localizedDescription)")
                    }
                }
                Toggle("Play sounds", isOn: $prefs.playSounds)
            }
            Section("After capture") {
                Toggle("Show Quick Access Overlay", isOn: $prefs.afterCaptureShowOverlay)
                Toggle("Copy to clipboard", isOn: $prefs.afterCaptureCopy)
                Toggle("Save to disk", isOn: $prefs.afterCaptureSave)
                Toggle("Open Annotate", isOn: $prefs.afterCaptureAnnotate)
                Toggle("Pin to screen", isOn: $prefs.afterCapturePin)
            }
            Section("Export") {
                HStack {
                    Text("Save to")
                    Spacer()
                    Text((prefs.saveFolder as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
                TextField("File name", text: $prefs.filenamePattern)
                Text("Tokens: {date} {time} {kind}").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { prefs.saveFolder = url.path }
    }
}

private struct ScreenshotSettings: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Format") {
                Picker("File format", selection: $prefs.imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.rawValue) { Text($0.rawValue.uppercased()).tag($0.rawValue) }
                }
                if prefs.imageFormat != "png" {
                    Slider(value: $prefs.jpegQuality, in: 0.3...1) { Text("Quality") }
                }
                Toggle("Scale Retina screenshots to 1x", isOn: $prefs.downscaleRetina)
                Toggle("Include the mouse cursor", isOn: $prefs.captureCursor)
            }
            Section("Selection") {
                Toggle("Show crosshair", isOn: $prefs.showCrosshair)
                Toggle("Show magnifier", isOn: $prefs.showMagnifier)
                Toggle("Freeze screen while selecting", isOn: $prefs.freezeScreen)
                Toggle("Hide desktop icons while capturing", isOn: $prefs.hideDesktopIconsOnCapture)
                Toggle("All-In-One remembers the last selection", isOn: $prefs.rememberAllInOne)
                Stepper("Self-timer: \(prefs.timerSeconds) s", value: $prefs.timerSeconds, in: 1...30)
            }
            Section("Window screenshots") {
                Picker("Background", selection: $prefs.windowBackground) {
                    Text("Transparent").tag("transparent")
                    Text("Desktop wallpaper").tag("wallpaper")
                    Text("Solid color").tag("solid")
                    Text("Gradient").tag("gradient")
                }
                Toggle("Window shadow", isOn: $prefs.windowShadow)
                if prefs.windowBackground != "transparent" {
                    Slider(value: $prefs.windowPadding, in: 0...200) { Text("Padding") }
                }
                if prefs.windowBackground == "solid" {
                    ColorPicker("Color", selection: hexBinding($prefs.windowSolidColor))
                }
                if prefs.windowBackground == "gradient" {
                    Stepper("Gradient \(prefs.windowGradientIndex + 1) of \(GradientPreset.all.count)",
                            value: $prefs.windowGradientIndex, in: 0...(GradientPreset.all.count - 1))
                }
            }
            Section {
                Toggle("Close after copying", isOn: $prefs.editorCloseAfterCopy)
                Toggle("Close after saving", isOn: $prefs.editorCloseAfterSave)
            } header: {
                Text("Annotate editor")
            } footer: {
                Text("Closing also dismisses the capture's Quick Access card. Project files stay open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RecordingSettings: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Video") {
                Picker("Frame rate", selection: $prefs.recFPS) {
                    ForEach([15, 24, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Quality", selection: $prefs.recQuality) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                Toggle("Record at Retina resolution", isOn: $prefs.recRetina)
                Toggle("Show cursor", isOn: $prefs.recShowCursor)
                Stepper("Countdown: \(prefs.recCountdown) s", value: $prefs.recCountdown, in: 0...10)
                Toggle("Hide desktop icons while recording", isOn: $prefs.recHideDesktopIcons)
            }
            Section("Audio") {
                Toggle("Record computer audio", isOn: $prefs.recSystemAudio)
                Toggle("Record microphone", isOn: $prefs.recMicrophone)
            }
            Section("GIF") {
                Picker("Frame rate", selection: $prefs.gifFPS) {
                    ForEach([10, 15, 20, 25], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Maximum width", selection: $prefs.gifMaxWidth) {
                    ForEach([480, 640, 960, 1280], id: \.self) { Text("\($0) px").tag($0) }
                }
            }
            Section("Clicks") {
                Toggle("Highlight clicks", isOn: $prefs.recHighlightClicks)
                ColorPicker("Color", selection: hexBinding($prefs.clickColor))
                Slider(value: $prefs.clickSize, in: 20...90) { Text("Size") }
                Toggle("Filled style", isOn: $prefs.clickFilled)
                Toggle("Animate", isOn: $prefs.clickAnimated)
            }
            Section("Keystrokes") {
                Toggle("Show keystrokes", isOn: $prefs.recShowKeystrokes)
                Toggle("Only shortcuts with ⌘ ⌃ ⌥", isOn: $prefs.keystrokeCommandsOnly)
                Picker("Position", selection: $prefs.keystrokePosition) {
                    Text("Bottom").tag("bottom")
                    Text("Top").tag("top")
                }
                Toggle("Light style", isOn: $prefs.keystrokeLight)
                Slider(value: $prefs.keystrokeSize, in: 14...40) { Text("Size") }
            }
            Section("Camera") {
                Toggle("Show camera", isOn: $prefs.recCamera)
                Picker("Shape", selection: $prefs.cameraShape) {
                    Text("Circle").tag("circle")
                    Text("Rounded square").tag("square")
                    Text("Wide").tag("wide")
                }
                Picker("Position", selection: $prefs.cameraPosition) {
                    Text("Bottom right").tag("bottomRight")
                    Text("Bottom left").tag("bottomLeft")
                    Text("Top right").tag("topRight")
                    Text("Top left").tag("topLeft")
                }
                Slider(value: $prefs.cameraSize, in: 100...480) { Text("Size") }
            }
        }
        .formStyle(.grouped)
    }
}

private struct OverlaySettings: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Picker("Position", selection: $prefs.overlayOnLeft) {
                Text("Left").tag(true)
                Text("Right").tag(false)
            }
            Slider(value: $prefs.overlaySize, in: 150...360) { Text("Size") }
            Toggle("Close automatically", isOn: $prefs.overlayAutoClose)
            if prefs.overlayAutoClose {
                Stepper("After \(prefs.overlayAutoCloseSeconds) s", value: $prefs.overlayAutoCloseSeconds, in: 3...300)
            }
            Toggle("Close after copying", isOn: $prefs.overlayCloseAfterCopy)
            Toggle("Close after saving", isOn: $prefs.overlayCloseAfterSave)
            Toggle("Close after dragging the file out", isOn: $prefs.overlayCloseAfterDrag)
            Text("Swipe a card sideways to dismiss it. Double-click to edit. Use Restore Recently Closed in the menu to bring one back.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    @ObservedObject private var hotkeys = HotkeyManager.shared

    var body: some View {
        Form {
            ForEach(AppAction.groups.filter { $0.title != "Window Snapping" }, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.actions, id: \.rawValue) { action in
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol).frame(width: 20).foregroundStyle(.secondary)
                            Text(action.title)
                            Spacer()
                            if hotkeys.failed.contains(action) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                    .help("Another app already uses this shortcut. Pick a different one.")
                            }
                            ShortcutRecorder(action: action, revision: hotkeys.revision).frame(width: 150, height: 26)
                        }
                    }
                }
            }
            Section("Window Snapping") {
                HStack {
                    Image(systemName: "rectangle.split.2x1").frame(width: 20).foregroundStyle(.secondary)
                    Text("Snapping shortcuts live with their layouts")
                    Spacer()
                    Button("Open Snapping…") { UserDefaults.standard.set(SettingsTab.snapping.rawValue, forKey: "settingsTab") }
                }
            }
            Section {
                HStack {
                    Button("Use ⌘⇧3 / ⌘⇧4 / ⌘⇧5") { hotkeys.applySystemStylePreset() }
                        .help("Fullscreen ⌘⇧3, Area ⌘⇧4, All-In-One ⌘⇧5, Window ⌘⇧6, Record ⌘⇧7, OCR ⌘⇧2")
                    Button("Open Keyboard Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") { NSWorkspace.shared.open(url) }
                    }
                    Spacer()
                    Button("Reset to Defaults") { hotkeys.resetToDefaults() }
                }
                Text("Click a field, then press the keys. ✕ or Delete clears it, Esc cancels. To use ⌘⇧3/4/5, first turn off macOS's own shortcuts in Keyboard Settings › Keyboard Shortcuts › Screenshots.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep captures for", selection: $prefs.historyRetentionDays) {
                    Text("1 day").tag(1)
                    Text("1 week").tag(7)
                    Text("1 month").tag(30)
                    Text("Forever").tag(0)
                }
                Button("Clear History…") {
                    let alert = NSAlert()
                    alert.messageText = "Delete all captures in history?"
                    alert.addButton(withTitle: "Delete")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn { HistoryStore.shared.clear() }
                }
            }
            Section("Permissions") {
                LabeledContent("Screen Recording", value: ScreenCapture.hasPermission ? "Granted" : "Not granted")
                LabeledContent("Accessibility", value: Permissions.ensureAccessibility(prompt: false) ? "Granted" : "Not granted")
                Text("Accessibility is only needed for keystroke display and auto-scroll.").font(.caption).foregroundStyle(.secondary)
            }
            Section("URL scheme") {
                Text("snapwise://capture-area · capture-fullscreen · capture-window · capture-previous-area · self-timer · scrolling-capture · all-in-one · record-screen · record-gif · capture-text · open-history · open-annotate?filepath= · pin?filepath= · toggle-desktop-icons · open-settings · snap-left-half · snap-right-half · snap-maximize · snap-top-left · snap-center · snap-next-display · snap-restore …")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

/// Bridges a `#RRGGBB` preference to a SwiftUI color well.
private func hexBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(nsColor: NSColor(hex: hex.wrappedValue)) }, set: { hex.wrappedValue = NSColor($0).hexString })
}
