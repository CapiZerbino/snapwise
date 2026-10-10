import AppKit
import ScreenCaptureKit
import SwiftUI

final class ScrollingCaptureState: ObservableObject {
    @Published var status = "Scroll slowly through the content"
    @Published var autoScroll = false
}

/// Repeatedly captures a fixed area while the user (or auto-scroll) scrolls, stitching the frames together.
final class ScrollingCaptureSession {
    private static var current: ScrollingCaptureSession?

    private let rect: CGRect
    private let screen: NSScreen
    private let completion: (CGImage?) -> Void
    private let state = ScrollingCaptureState()
    private var stitcher = ScrollStitcher()
    private var border: RecordingBorder?
    private var panel: OverlayPanel?
    private var loop: Task<Void, Never>?
    private var idleFrames = 0
    private let maxLines = 40_000

    static func start(rect: CGRect, screen: NSScreen, completion: @escaping (CGImage?) -> Void) {
        current?.finish(keep: false)
        let session = ScrollingCaptureSession(rect: rect, screen: screen, completion: completion)
        current = session
        session.begin()
    }

    private init(rect: CGRect, screen: NSScreen, completion: @escaping (CGImage?) -> Void) {
        self.rect = rect
        self.screen = screen
        self.completion = completion
    }

    private func begin() {
        border = RecordingBorder(area: rect)
        let view = ScrollingControls(state: state, onDone: { [weak self] in self?.finish(keep: true) },
                                     onCancel: { [weak self] in self?.finish(keep: false) },
                                     onAutoScrollChanged: { [weak self] in self?.autoScrollChanged() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 14)
        if origin.y < screen.visibleFrame.minY + 4 { origin.y = rect.maxY + 14 }
        if origin.y + size.height > screen.frame.maxY { origin.y = rect.minY + 14 }
        let panel = OverlayPanel(frame: CGRect(origin: origin, size: size), level: .screenSaver)
        panel.allowsKey = false
        panel.hasShadow = true
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel

        loop = Task { @MainActor [weak self] in await self?.run() }
    }

    private func autoScrollChanged() {
        if state.autoScroll, !Permissions.ensureAccessibility() {
            state.autoScroll = false
            Toast.show("Grant Accessibility access to auto-scroll")
        }
    }

    @MainActor
    private func run() async {
        guard let content = try? await ScreenCapture.content(),
              let filter = try? ScreenCapture.displayFilter(screen: screen, content: content, forRecording: false) else {
            Toast.show("Scrolling capture failed to start")
            return finish(keep: false)
        }
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = screen.localTopLeft(rect)
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best

        while !Task.isCancelled {
            if let frame = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                if Task.isCancelled { return }
                let grew = stitcher.add(frame)
                idleFrames = grew ? 0 : idleFrames + 1
                let total = (stitcher.axis == .horizontal ? frame.width : frame.height) + stitcher.addedLines
                state.status = stitcher.addedLines == 0 ? "Scroll slowly through the content" : "Captured \(Int(CGFloat(total) / scale)) pt"
                // Auto-scroll stops by itself once the page no longer moves.
                if total >= maxLines || (state.autoScroll && idleFrames >= 10 && stitcher.addedLines > 0) { return finish(keep: true) }
            }
            if state.autoScroll { postScroll() }
            try? await Task.sleep(nanoseconds: state.autoScroll ? 140_000_000 : 70_000_000)
        }
    }

    private func postScroll() {
        let step = Int32(max(20, rect.height / 6))
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0) else { return }
        event.location = Geo.flipGlobal(CGRect(origin: rect.center, size: .zero)).origin
        event.post(tap: .cghidEventTap)
    }

    private func finish(keep: Bool) {
        guard ScrollingCaptureSession.current === self else { return }
        ScrollingCaptureSession.current = nil
        loop?.cancel()
        border?.close()
        panel?.close()
        completion(keep ? stitcher.result() : nil)
    }
}

struct ScrollingControls: View {
    @ObservedObject var state: ScrollingCaptureState
    let onDone: () -> Void
    let onCancel: () -> Void
    let onAutoScrollChanged: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.text.horizontal")
            Text(state.status).monospacedDigit().frame(minWidth: 210, alignment: .leading)
            Toggle("Auto-scroll", isOn: $state.autoScroll)
                .toggleStyle(.button)
                .onChange(of: state.autoScroll) { _, _ in onAutoScrollChanged() }
            Button("Cancel", action: onCancel)
            Button("Done", action: onDone).buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}
