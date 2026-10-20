import SwiftUI

/// Settings for the drag & convert wheel.
struct ConvertSettings: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @State private var trusted = WindowAX.isTrusted
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.18))
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 22, weight: .semibold)).foregroundStyle(.orange)
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("Drag & Convert", isOn: $prefs.convertEnabled).font(.headline)
                            .onChange(of: prefs.convertEnabled) { _, _ in FileDragMonitor.shared.refresh() }
                        Text("While dragging files, tap a key to open a wheel, then drop on a bubble. Results are saved next to the original; nothing is uploaded.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                if !trusted {
                    HStack {
                        Image(systemName: "lock.shield").foregroundStyle(.yellow)
                        Text("Needs Accessibility access to notice key taps in other apps.").font(.caption)
                        Spacer()
                        Button("Grant Access…") { _ = Permissions.ensureAccessibility() }
                    }
                }
            }
            Section("Keys") {
                ForEach(WheelKind.allCases, id: \.rawValue) { kind in
                    HStack {
                        Image(systemName: kind.symbol).frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                            Text(detail(kind)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: binding(for: kind)) {
                            ForEach(WheelTrigger.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }
                Text("Tap means press and release the key on its own. Tapping another key switches wheels; Esc or releasing the drag elsewhere closes it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!prefs.convertEnabled)
            Section("Without dragging") {
                HStack {
                    Text("Convert Files…")
                    Text("pick files, then click a bubble or use ← → ↩ and Tab").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ShortcutRecorder(action: .convertFiles, revision: hotkeys.revision).frame(width: 130, height: 24)
                }
            }
            Section("Formats") {
                formats("Images", "PNG, JPG, HEIC, AVIF, TIFF, GIF, BMP, PDF, ICO, ICNS (reads WebP, SVG, RAW too)")
                formats("Video", "MP4, MOV, M4A audio, GIF")
                formats("Audio", "M4A, WAV, AIFF, FLAC, CAF (reads MP3)")
                formats("PDF", "PNG or JPG pages at 300 DPI, TXT, RTF")
                formats("Documents", "DOCX, PDF, RTF, HTML, TXT, ODT (reads DOC, Markdown)")
                formats("Tables", "CSV, TSV, HTML")
                formats("Any file", "ZIP, TAR.GZ; extracts ZIP, TAR, GZ")
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = WindowAX.isTrusted }
    }

    private func detail(_ kind: WheelKind) -> String {
        switch kind {
        case .convert: return "Change the format"
        case .tools: return "Compress, resize, rotate, cut out, merge, split, extract…"
        case .actions: return "AirDrop, float, copy, move, copy path, Terminal"
        }
    }

    private func formats(_ title: String, _ list: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).frame(width: 80, alignment: .leading)
            Text(list).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Picking a key that another wheel already uses swaps the two, so each key opens exactly one wheel.
    private func binding(for kind: WheelKind) -> Binding<String> {
        Binding {
            kind.trigger.rawValue
        } set: { value in
            let previous = kind.trigger.rawValue
            if let other = WheelKind.allCases.first(where: { $0 != kind && $0.trigger.rawValue == value }) { set(other, previous) }
            set(kind, value)
        }
    }

    private func set(_ kind: WheelKind, _ value: String) {
        switch kind {
        case .convert: prefs.convertKeyConvert = value
        case .tools: prefs.convertKeyTools = value
        case .actions: prefs.convertKeyActions = value
        }
    }
}
