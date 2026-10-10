import AppKit
import SwiftUI

/// Window-level commands the toolbar triggers; implemented by `EditorWindowController`.
struct EditorActions {
    var copy: () -> Void = {}
    var save: () -> Void = {}
    var saveAs: () -> Void = {}
    var saveProject: () -> Void = {}
    var done: () -> Void = {}
    var pin: () -> Void = {}
    var share: () -> Void = {}
    var resize: () -> Void = {}
    var dragURL: () -> URL? = { nil }
}

enum ZoomCommand {
    case zoomIn, zoomOut, fit, actual
}

struct EditorRootView: View {
    @ObservedObject var model: EditorModel
    let actions: EditorActions

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model, actions: actions)
            Divider()
            HStack(spacing: 0) {
                EditorCanvas(model: model)
                if model.showInspector {
                    Divider()
                    BackgroundInspector(model: model)
                }
            }
            Divider()
            EditorStatusBar(model: model)
        }
        .frame(minWidth: 900, minHeight: 520)
    }
}

/// Square icon button used across the editor chrome.
private struct IconButton: View {
    let symbol: String
    let help: String
    var selected = false
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(disabled ? 0.3 : 0.85))
                .frame(width: 32, height: 28)
                .background(selected ? Color.accentColor : (hovering && !disabled ? Color.primary.opacity(0.1) : .clear),
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Rounded tray that visually groups related toolbar controls.
private struct Tray<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var prefs = Prefs.shared
    let actions: EditorActions

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Tray {
                    ForEach(Tool.toolbar, id: \.self) { tool in
                        IconButton(symbol: tool.symbol, help: tool.title, selected: model.tool == tool) { model.tool = tool }
                    }
                }
                Tray {
                    IconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", disabled: model.undoStack.isEmpty) { model.undo() }
                    IconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", disabled: model.redoStack.isEmpty) { model.redo() }
                    Menu {
                        Button("Rotate Left") { model.rotate(clockwise: false) }
                        Button("Rotate Right") { model.rotate(clockwise: true) }
                        Button("Flip Horizontal") { model.flip(horizontal: true) }
                        Button("Flip Vertical") { model.flip(horizontal: false) }
                        Divider()
                        Button("Resize…", action: actions.resize)
                        Button("Auto Balance") { model.autoBalance() }
                    } label: {
                        Image(systemName: "rotate.right").font(.system(size: 14, weight: .medium)).frame(width: 32, height: 28)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Rotate, flip, resize")
                    IconButton(symbol: "photo.on.rectangle.angled", help: "Background tool", selected: model.showInspector) {
                        model.showInspector.toggle()
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Image(systemName: "hand.draw.fill")
                    Text("Drag me")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .onDrag { actions.dragURL().flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
                .help("Drag the result into another app")
                Tray {
                    IconButton(symbol: "pin", help: "Pin to screen", action: actions.pin)
                    IconButton(symbol: "square.and.arrow.up", help: "Share…", action: actions.share)
                    Menu {
                        Button("Save to \((prefs.saveFolder as NSString).lastPathComponent)", action: actions.save)
                        Button("Save As…", action: actions.saveAs)
                        Button("Save Project…", action: actions.saveProject)
                    } label: {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 14, weight: .medium)).frame(width: 32, height: 28)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Save (⌘S)")
                }
                Button("Copy", action: actions.copy).controlSize(.large).help("Copy (⌘C)")
                Button("Done", action: actions.done).controlSize(.large).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).help("Apply the changes and close")
            }
            HStack(spacing: 10) {
                options
                Spacer()
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var activeTool: Tool { model.selected?.tool ?? model.tool }

    @ViewBuilder private var options: some View {
        if model.tool == .crop {
            Picker("Aspect", selection: $model.cropAspect) {
                ForEach(["free", "1:1", "4:3", "3:2", "16:9", "9:16"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            .frame(width: 150)
            Button("Apply Crop") { model.applyCrop() }.disabled(model.cropRect == nil)
            Text("Drag to choose the area, then press Return").font(.caption).foregroundStyle(.secondary)
        } else if model.tool == .select && model.selected == nil {
            Text("Click an annotation to move, resize or restyle it. Delete removes it.").font(.caption).foregroundStyle(.secondary)
        } else {
            swatches
            if ![.text, .counter, .blur, .spotlight, .filledRect, .image].contains(activeTool) {
                Divider().frame(height: 16)
                Image(systemName: "lineweight").foregroundStyle(.secondary)
                Slider(value: $model.lineWidth, in: 1...20).frame(width: 110)
            }
            if activeTool == .arrow {
                Picker("", selection: $model.arrowStyle) {
                    ForEach(ArrowStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }
            if [.text, .counter].contains(activeTool) {
                Divider().frame(height: 16)
                Image(systemName: "textformat.size").foregroundStyle(.secondary)
                Slider(value: $model.fontSize, in: 10...72).frame(width: 110)
            }
            if activeTool == .text {
                Picker("", selection: $model.textStyle) {
                    ForEach(TextStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 130)
            }
            if activeTool == .blur {
                Picker("", selection: $model.blurStyle) {
                    ForEach(BlurStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
        }
    }

    private var swatches: some View {
        HStack(spacing: 6) {
            ForEach(RGBA.palette + prefs.customPalette.map(RGBA.init(hex:)), id: \.self) { color in
                Circle().fill(Color(nsColor: color.ns))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                    .padding(3)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: model.color == color ? 2 : 0))
                    .onTapGesture { model.color = color }
            }
            ColorPicker("", selection: Binding(get: { Color(nsColor: model.color.ns) }, set: { model.color = RGBA(NSColor($0)) }))
                .labelsHidden()
            Button {
                var saved = prefs.customPalette.filter { $0 != model.color.ns.hexString }
                saved.append(model.color.ns.hexString)
                prefs.customPalette = Array(saved.suffix(8))
            } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless).help("Save this color to the palette")
        }
    }
}

struct EditorStatusBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            Text("\(Int(model.layout.canvas.width)) × \(Int(model.layout.canvas.height)) px").monospacedDigit()
            Text(hint).foregroundStyle(.tertiary).lineLimit(1)
            Spacer()
            Button { model.zoomCommand?(.zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
            Menu("\(Int((model.zoom * 100).rounded()))%") {
                Button("Zoom to Fit") { model.zoomCommand?(.fit) }
                Button("Actual Size") { model.zoomCommand?(.actual) }
            }
            .menuStyle(.borderlessButton).fixedSize().monospacedDigit()
            Button { model.zoomCommand?(.zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }

    private var hint: String {
        switch model.tool {
        case .select: return "Drag to move · handles resize · arrow keys nudge"
        case .crop: return "Drag an area · Return applies · Esc cancels"
        case .text: return "Click to type · Return commits · double-click to edit"
        case .counter: return "Click to place the next number"
        case .pencil: return "Draw freehand"
        default: return "Drag to draw · hold ⇧ to constrain · the new shape stays selected for tweaks"
        }
    }
}

struct BackgroundInspector: View {
    @ObservedObject var model: EditorModel
    @State private var presets = BackgroundSettings.loadPresets()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Background", isOn: $model.background.enabled).toggleStyle(.switch)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 5), spacing: 6) {
                    ForEach(GradientPreset.all.indices, id: \.self) { index in
                        let preset = GradientPreset.at(index)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: preset.from)), Color(nsColor: NSColor(hex: preset.to))],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                model.background.kind == "gradient" && model.background.gradientIndex == index ? Color.accentColor : .clear, lineWidth: 2))
                            .onTapGesture {
                                model.background.kind = "gradient"
                                model.background.gradientIndex = index
                                model.background.enabled = true
                            }
                    }
                }
                HStack {
                    ColorPicker("Solid", selection: Binding(get: { Color(nsColor: model.background.solid.ns) }, set: {
                        model.background.solid = RGBA(NSColor($0))
                        model.background.kind = "solid"
                        model.background.enabled = true
                    }))
                    Spacer()
                    Button("Image…", action: chooseImage)
                }
                slider("Padding", $model.background.padding, 0...240)
                slider("Corners", $model.background.cornerRadius, 0...48)
                slider("Shadow", $model.background.shadow, 0...1)
                Picker("Ratio", selection: $model.background.aspect) {
                    ForEach(BackgroundSettings.aspects, id: \.self) { Text($0.capitalized).tag($0) }
                }
                HStack(alignment: .top) {
                    Text("Align")
                    Spacer()
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        ForEach(0..<3, id: \.self) { row in
                            GridRow {
                                ForEach(0..<3, id: \.self) { column in
                                    let index = row * 3 + column
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(model.background.alignment == index ? Color.accentColor : Color.secondary.opacity(0.3))
                                        .frame(width: 18, height: 14)
                                        .onTapGesture { model.background.alignment = index }
                                }
                            }
                        }
                    }
                }
                Button("Auto Balance") { model.autoBalance() }
                    .help("Crop uneven margins so the content is centered")
                Divider()
                HStack {
                    Text("Presets").font(.headline)
                    Spacer()
                    Button("Save") {
                        presets.append(model.background)
                        BackgroundSettings.savePresets(presets)
                    }
                }
                ForEach(presets.indices, id: \.self) { index in
                    HStack {
                        Button("Preset \(index + 1)") {
                            model.background = presets[index]
                            model.background.enabled = true
                        }
                        Spacer()
                        Button {
                            presets.remove(at: index)
                            BackgroundSettings.savePresets(presets)
                        } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 228)
    }

    private func slider(_ title: String, _ value: Binding<CGFloat>, _ range: ClosedRange<CGFloat>) -> some View {
        HStack {
            Text(title).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        model.background.imageData = data
        model.background.kind = "image"
        model.background.enabled = true
    }
}
