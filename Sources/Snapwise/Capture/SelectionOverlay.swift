import AppKit
import SwiftUI

enum AreaAction {
    case screenshot, video, gif, scrolling, ocr
}

enum SelectionResult {
    /// `rect` is in AppKit global coordinates; `frozen` is the already-cropped snapshot when the screen was frozen.
    case area(rect: CGRect, screen: NSScreen, action: AreaAction, frozen: CGImage?)
    case window(WindowInfo)
    case fullscreen(NSScreen)
    case cancelled
}

/// Size fields and aspect lock shown in the All-In-One toolbar.
final class AllInOneState: ObservableObject {
    @Published var width = ""
    @Published var height = ""
    @Published var lockAspect = false
    /// Recording bar only: record a GIF instead of a video.
    @Published var gif = false
}

/// Presents one selection panel per display and reports a single result.
final class SelectionOverlay {
    private static var current: SelectionOverlay?
    static var isActive: Bool { current != nil }

    private var panels: [OverlayPanel] = []
    private var views: [SelectionView] = []
    private var toolbar: OverlayPanel?
    private let toolbarState = AllInOneState()
    private var mode: SelectionMode
    private let initialMode: SelectionMode
    private let completion: (SelectionResult) -> Void

    static func begin(mode: SelectionMode, recordGIF: Bool = false, snapshots: [CGDirectDisplayID: CGImage],
                      completion: @escaping (SelectionResult) -> Void) {
        current?.finish(.cancelled)
        let overlay = SelectionOverlay(mode: mode, completion: completion)
        overlay.toolbarState.gif = recordGIF
        current = overlay
        overlay.present(snapshots: snapshots)
    }

    static func cancel() { current?.finish(.cancelled) }

    private init(mode: SelectionMode, completion: @escaping (SelectionResult) -> Void) {
        self.mode = mode
        self.initialMode = mode
        self.completion = completion
    }

    private func present(snapshots: [CGDirectDisplayID: CGImage]) {
        let windows = WindowList.onScreen()
        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        for screen in NSScreen.screens {
            let view = SelectionView(screen: screen, mode: mode, snapshot: snapshots[screen.displayID],
                                     frozen: Prefs.shared.freezeScreen, windows: windows)
            view.hint = hint(for: mode)
            view.onCancel = { [weak self] in self?.finish(.cancelled) }
            view.onWindow = { [weak self] in self?.finish(.window($0)) }
            view.onFullscreen = { [weak self] in self?.finish(.fullscreen(screen)) }
            view.onToggleMode = { [weak self] in self?.toggleWindowMode() }
            view.onArea = { [weak self, weak view] rect in
                guard let self, let view else { return }
                self.finishArea(rect, view: view, action: self.confirmAction)
            }
            view.onConfirm = { [weak self, weak view] in
                guard let self, let view, let rect = view.globalSelection else { return }
                self.finishArea(rect, view: view, action: self.confirmAction)
            }
            view.onSelectionChanged = { [weak self, weak view] rect in
                guard let self, let view, self.initialMode == .allInOne || self.initialMode == .record else { return }
                self.selectionChanged(rect, in: view)
            }
            let panel = OverlayPanel(frame: screen.frame, level: level)
            panel.contentView = view
            panel.acceptsMouseMovedEvents = true
            panel.orderFrontRegardless()
            panels.append(panel)
            views.append(view)
        }
        let active = views.first { $0.screen.frame.contains(NSEvent.mouseLocation) } ?? views.first
        active?.window?.makeKey()
        active?.window?.makeFirstResponder(active)
        NSCursor.crosshair.set()

        if mode == .allInOne, Prefs.shared.rememberAllInOne, let active {
            let saved = NSRectFromString(Prefs.shared.allInOneArea)
            if saved.width > 8, saved.height > 8, active.bounds.contains(saved) { active.setSelection(saved, adjusting: true) }
        }
    }

    /// What Return (or finishing a plain drag) does in the current mode.
    private var confirmAction: AreaAction {
        guard initialMode == .record else { return .screenshot }
        return toolbarState.gif ? .gif : .video
    }

    private func hint(for mode: SelectionMode) -> String {
        switch mode {
        case .area: return "Drag to capture · Space: window · F: full screen · Esc: cancel"
        case .window: return "Click a window · Space: area · Esc: cancel"
        case .allInOne: return "Drag to select, then pick an action · Esc: cancel"
        case .record: return "Drag to choose what to record · Space: window · F: full screen · Esc: cancel"
        }
    }

    private func toggleWindowMode() {
        guard initialMode != .allInOne else { return }
        mode = mode == .window ? initialMode == .window ? .area : initialMode : .window
        views.forEach {
            $0.mode = mode
            $0.hint = hint(for: mode)
            $0.clearSelection()
        }
    }

    private func finishArea(_ rect: CGRect, view: SelectionView, action: AreaAction) {
        var frozen: CGImage?
        if view.frozen, let snapshot = view.snapshot, action == .screenshot || action == .ocr {
            let scale = CGFloat(snapshot.width) / view.screen.frame.width
            frozen = snapshot.cropping(to: view.screen.localTopLeft(rect).scaled(by: scale).integral)
        }
        if initialMode == .allInOne, let local = view.selection { Prefs.shared.allInOneArea = NSStringFromRect(local) }
        finish(.area(rect: rect, screen: view.screen, action: action, frozen: frozen))
    }

    private func finish(_ result: SelectionResult) {
        guard SelectionOverlay.current === self else { return }
        SelectionOverlay.current = nil
        toolbar?.close()
        panels.forEach { $0.close() }
        NSCursor.arrow.set()
        completion(result)
    }

    // MARK: - All-In-One toolbar

    private func selectionChanged(_ rect: CGRect?, in view: SelectionView) {
        // Only one display can own the selection.
        views.filter { $0 !== view && $0.selection != nil }.forEach { $0.clearSelection() }
        guard let rect, view.adjusting else {
            toolbar?.orderOut(nil)
            if let rect { syncFields(rect) }
            return
        }
        syncFields(rect)
        if toolbar == nil { toolbar = makeToolbar() }
        guard let toolbar else { return }
        let size = toolbar.frame.size
        let global = rect.offsetBy(dx: view.screen.frame.minX, dy: view.screen.frame.minY)
        var origin = CGPoint(x: global.midX - size.width / 2, y: global.minY - size.height - 12)
        if origin.y < view.screen.frame.minY + 8 { origin.y = global.minY + 12 }
        origin.x = max(view.screen.frame.minX + 8, min(view.screen.frame.maxX - size.width - 8, origin.x))
        toolbar.setFrameOrigin(origin)
        toolbar.orderFrontRegardless()
    }

    private func syncFields(_ rect: CGRect) {
        toolbarState.width = String(Int(rect.width))
        toolbarState.height = String(Int(rect.height))
    }

    private var selectedView: SelectionView? { views.first { $0.selection != nil } }

    private func makeToolbar() -> OverlayPanel {
        let act: (AreaAction) -> Void = { [weak self] action in
            guard let self, let view = self.selectedView, let rect = view.globalSelection else { return }
            self.finishArea(rect, view: view, action: action)
        }
        let cancel: () -> Void = { [weak self] in self?.finish(.cancelled) }
        let host: NSView
        if initialMode == .record {
            host = NSHostingView(rootView: RecordToolbar(state: toolbarState, onStart: { [weak self] in
                act(self?.toolbarState.gif == true ? .gif : .video)
            }, onCancel: cancel))
        } else {
            host = NSHostingView(rootView: AllInOneToolbar(state: toolbarState, onAction: act, onResize: { [weak self] in
                self?.applyFieldSize()
            }, onLockChanged: { [weak self] in
                guard let self, let view = self.selectedView, let sel = view.selection else { return }
                view.lockedAspect = self.toolbarState.lockAspect ? sel.width / sel.height : nil
            }, onCancel: cancel))
        }
        let size = host.fittingSize
        let panel = OverlayPanel(frame: CGRect(origin: .zero, size: size), level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1))
        panel.contentView = host
        panel.hasShadow = true
        return panel
    }

    private func applyFieldSize() {
        guard let view = selectedView, let sel = view.selection,
              let w = Double(toolbarState.width), let h = Double(toolbarState.height), w >= 8, h >= 8 else { return }
        // Anchor the top-left corner, which is what the user sees as the origin.
        view.setSelection(CGRect(x: sel.minX, y: sel.maxY - h, width: w, height: h), adjusting: true)
        if toolbarState.lockAspect { view.lockedAspect = w / h }
    }
}

/// Shared look of the floating bars under a selection.
private struct FloatingBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.18)))
            .environment(\.colorScheme, .dark)
            .fixedSize()
    }
}

private struct BarButton: View {
    let symbol: String
    let title: String
    var tint: Color = .white
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(height: 18)
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(width: 62, height: 44)
            .background(hovering ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// On/off option in the recording bar.
private struct BarToggle: View {
    let symbol: String
    let help: String
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn && !disabled ? Color.black : Color.white.opacity(disabled ? 0.3 : 0.85))
                .frame(width: 34, height: 30)
                .background(isOn && !disabled ? Color.white : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

struct AllInOneToolbar: View {
    @ObservedObject var state: AllInOneState
    let onAction: (AreaAction) -> Void
    let onResize: () -> Void
    let onLockChanged: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            BarButton(symbol: "camera.viewfinder", title: "Capture") { onAction(.screenshot) }
            BarButton(symbol: "video", title: "Video") { onAction(.video) }
            BarButton(symbol: "photo.stack", title: "GIF") { onAction(.gif) }
            BarButton(symbol: "arrow.up.and.down.square", title: "Scroll") { onAction(.scrolling) }
            BarButton(symbol: "text.viewfinder", title: "OCR") { onAction(.ocr) }
            Divider().frame(height: 30).padding(.horizontal, 6)
            TextField("W", text: $state.width).frame(width: 54).onSubmit(onResize)
            Text("×").foregroundStyle(.secondary)
            TextField("H", text: $state.height).frame(width: 54).onSubmit(onResize)
            BarToggle(symbol: state.lockAspect ? "lock.fill" : "lock.open", help: "Lock aspect ratio", isOn: $state.lockAspect)
                .padding(.leading, 4)
                .onChange(of: state.lockAspect) { _, _ in onLockChanged() }
            Divider().frame(height: 30).padding(.horizontal, 6)
            BarButton(symbol: "xmark", title: "Cancel", tint: .white.opacity(0.7), action: onCancel)
        }
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.center)
        .modifier(FloatingBar())
    }
}

/// Shown under the selection before a recording starts: format, capture options, then Record.
struct RecordToolbar: View {
    @ObservedObject var state: AllInOneState
    @ObservedObject private var prefs = Prefs.shared
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $state.gif) {
                Text("Video").tag(false)
                Text("GIF").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            Divider().frame(height: 26)
            BarToggle(symbol: "mic.fill", help: "Record microphone", isOn: $prefs.recMicrophone, disabled: state.gif)
            BarToggle(symbol: "speaker.wave.2.fill", help: "Record computer audio", isOn: $prefs.recSystemAudio, disabled: state.gif)
            BarToggle(symbol: "web.camera.fill", help: "Show camera", isOn: $prefs.recCamera, disabled: state.gif)
            BarToggle(symbol: "cursorarrow.rays", help: "Highlight clicks", isOn: $prefs.recHighlightClicks)
            BarToggle(symbol: "keyboard.fill", help: "Show keystrokes", isOn: $prefs.recShowKeystrokes)
            BarToggle(symbol: "cursorarrow", help: "Show cursor", isOn: $prefs.recShowCursor)
            Divider().frame(height: 26)
            Text("\(state.width) × \(state.height)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.7)).frame(minWidth: 74)
            Button(action: onStart) {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 9, height: 9)
                    Text("Record").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Start recording (Return)")
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 30)
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        }
        .modifier(FloatingBar())
    }
}
