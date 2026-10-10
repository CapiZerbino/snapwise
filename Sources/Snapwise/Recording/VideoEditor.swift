import AppKit
import AVKit
import SwiftUI

final class VideoEditorModel: ObservableObject {
    let url: URL
    let asset: AVURLAsset
    let player: AVPlayer
    let clicks: [ClickEvent]

    @Published var duration: Double = 0
    @Published var options = VideoExportOptions() { didSet { if options != oldValue { optionsChanged(oldValue) } } }
    @Published var exporting = false
    private var loading = true

    init(url: URL, clicksURL: URL?) {
        self.url = url
        asset = AVURLAsset(url: url)
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        clicks = clicksURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([ClickEvent].self, from: $0) } ?? []
        Task { @MainActor in
            duration = (try? await asset.load(.duration).seconds) ?? 0
            options.end = duration
            loading = false
        }
    }

    private func optionsChanged(_ old: VideoExportOptions) {
        guard !loading else { return } // the initial trim range must not move the playhead
        if options.start != old.start { seek(options.start) }
        if options.end != old.end { seek(options.end) }
        var a = options, b = old
        a.start = 0; a.end = 0; b.start = 0; b.end = 0
        if a != b { refreshPreview() }
    }

    private func seek(_ seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Applies the same effect pipeline the export uses to the live player.
    private func refreshPreview() {
        let options = options
        Task { @MainActor in
            player.currentItem?.videoComposition = try? await VideoExporter.composition(asset: asset, options: options, clicks: clicks)
            player.isMuted = options.mute
        }
    }

    func export(asGIF: Bool) {
        guard !exporting, options.end - options.start > 0.1 else { return }
        exporting = true
        player.pause()
        let options = options
        Task { @MainActor in
            defer { exporting = false }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("snapwise-\(UUID().uuidString).mp4")
            do {
                try await VideoExporter.export(asset: asset, options: options, clicks: clicks, to: temp)
                let size = try await AVURLAsset(url: temp).loadTracks(withMediaType: .video).first?.load(.naturalSize)
                    ?? VideoExporter.layout(natural: CGSize(width: 1280, height: 720), options: options).canvas
                var final = temp
                if asGIF {
                    final = temp.deletingPathExtension().appendingPathExtension("gif")
                    try await GIFExporter.export(videoURL: temp, to: final, fps: Prefs.shared.gifFPS, maxWidth: Prefs.shared.gifMaxWidth)
                    try? FileManager.default.removeItem(at: temp)
                }
                guard let item = HistoryStore.shared.add(fileAt: final, kind: asGIF ? .gif : .video, pixelSize: size, scale: 1) else {
                    return Toast.show("Could not store the export")
                }
                if let saved = Output.save(fileAt: item.url, kind: item.kind.label) { Toast.show("Exported to \(saved.lastPathComponent)") }
                QuickAccessManager.shared.show(item)
            } catch {
                Toast.show("Export failed: \(error.localizedDescription)")
            }
        }
    }
}

enum VideoEditorWindowController {
    private static var windows: [NSWindow] = []

    static func open(url: URL, clicksURL: URL?) {
        let model = VideoEditorModel(url: url, clicksURL: clicksURL)
        let window = WindowFactory.make(title: "Edit Recording", size: CGSize(width: 980, height: 620)) { VideoEditorView(model: model) }
        windows.append(window)
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            model.player.pause()
            windows.removeAll { $0 === window }
            // The block retains the window and model; drop it so they can be freed.
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
        WindowFactory.present(window)
    }
}

struct VideoEditorView: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                VideoPlayer(player: model.player)
                trimControls
            }
            .padding(12)
            Divider()
            inspector.frame(width: 250)
        }
        .frame(minWidth: 820, minHeight: 500)
    }

    private var trimControls: some View {
        let last = max(model.duration, 0.2)
        return VStack(spacing: 4) {
            HStack {
                Text("Start").frame(width: 40, alignment: .leading)
                Slider(value: $model.options.start, in: 0...max(0.1, model.options.end - 0.1))
                Text(timeText(model.options.start)).monospacedDigit().frame(width: 56)
            }
            HStack {
                Text("End").frame(width: 40, alignment: .leading)
                Slider(value: $model.options.end, in: min(last - 0.05, model.options.start + 0.1)...last)
                Text(timeText(model.options.end)).monospacedDigit().frame(width: 56)
            }
        }
    }

    private var inspector: some View {
        Form {
            Section("Format") {
                Picker("Canvas", selection: $model.options.format) {
                    Text("Original").tag("original")
                    Text("Landscape 16:9").tag("16:9")
                    Text("Square 1:1").tag("1:1")
                    Text("Vertical 9:16").tag("9:16")
                }
                Picker("Resolution", selection: $model.options.maxHeight) {
                    Text("Original").tag(0)
                    Text("2160p").tag(2160)
                    Text("1080p").tag(1080)
                    Text("720p").tag(720)
                }
            }
            Section("Background") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 5), count: 6), spacing: 5) {
                    swatch(index: -1)
                    ForEach(GradientPreset.all.indices, id: \.self) { swatch(index: $0) }
                }
                if model.options.backgroundIndex >= 0 {
                    Slider(value: $model.options.padding, in: 0...0.2) { Text("Padding") }
                    Slider(value: $model.options.cornerRadius, in: 0...40) { Text("Corners") }
                }
            }
            Section("Auto Zoom") {
                Toggle("Zoom in on clicks", isOn: $model.options.zoomOnClicks).disabled(model.clicks.isEmpty)
                if model.clicks.isEmpty {
                    Text("No clicks were recorded for this video.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Slider(value: $model.options.zoomScale, in: 1.2...3) { Text("Level") }
                }
            }
            Section("Audio") {
                Toggle("Mute audio", isOn: $model.options.mute)
            }
            Section {
                HStack {
                    Button("Export MP4") { model.export(asGIF: false) }.keyboardShortcut(.defaultAction)
                    Button("Export GIF") { model.export(asGIF: true) }
                    if model.exporting { ProgressView().controlSize(.small) }
                }
                .disabled(model.exporting)
            }
        }
        .formStyle(.grouped)
    }

    private func swatch(index: Int) -> some View {
        let selected = model.options.backgroundIndex == index
        return Group {
            if index < 0 {
                RoundedRectangle(cornerRadius: 5).fill(.black).overlay(Image(systemName: "nosign").font(.caption).foregroundStyle(.white))
            } else {
                let preset = GradientPreset.at(index)
                RoundedRectangle(cornerRadius: 5).fill(LinearGradient(
                    colors: [Color(nsColor: NSColor(hex: preset.from)), Color(nsColor: NSColor(hex: preset.to))],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: 30, height: 22)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .onTapGesture { model.options.backgroundIndex = index }
    }

    private func timeText(_ seconds: Double) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}
