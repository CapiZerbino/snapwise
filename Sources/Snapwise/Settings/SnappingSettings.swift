import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Miniature screen with the snapped region filled in; clearer than a generic icon for telling positions apart.
struct SnapGlyph: View {
    let position: SnapPosition
    var size = CGSize(width: 30, height: 20)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.25))
            if let f = position.fractions {
                RoundedRectangle(cornerRadius: 2.5).fill(Color.accentColor)
                    .frame(width: max(4, (size.width - 4) * f.width), height: max(4, (size.height - 4) * f.height))
                    .offset(x: 2 + (size.width - 4) * f.minX, y: 2 + (size.height - 4) * f.minY)
            } else {
                Image(systemName: position.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct SnappingSettings: View {
    private enum Pane: String, CaseIterable {
        case layouts = "Layouts", dragging = "Dragging", buttons = "Buttons", areas = "Areas", apps = "Apps"
    }

    @ObservedObject private var prefs = Prefs.shared
    @AppStorage("snappingPane") private var selected = Pane.layouts.rawValue
    @State private var trusted = WindowAX.isTrusted
    @State private var nativeTiling = NativeTiling.isEnabled
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var pane: Pane { Pane(rawValue: selected) ?? .layouts }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: $prefs.snapEnabled).toggleStyle(.switch).labelsHidden()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Window Snapping").font(.headline)
                    Text(prefs.snapEnabled ? "Drag windows to screen edges or use shortcuts to arrange them." : "Off — shortcuts and drag snapping are inactive.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            banners

            Picker("", selection: $selected) {
                ForEach(Pane.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()
            Group {
                switch pane {
                case .layouts: SnapLayoutsPane()
                case .dragging: SnapDraggingPane()
                case .buttons: SnapButtonsPane()
                case .areas: SnapAreasPane()
                case .apps: SnapAppsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(!prefs.snapEnabled)
            .opacity(prefs.snapEnabled ? 1 : 0.5)
        }
        .frame(width: 640)
        .onReceive(timer) { _ in
            trusted = WindowAX.isTrusted
            nativeTiling = NativeTiling.isEnabled
        }
        .onChange(of: prefs.snapEnabled) { _, _ in SnapSettingsActions.apply() }
    }

    @ViewBuilder private var banners: some View {
        if !trusted {
            banner(symbol: "lock.shield", tint: .yellow, title: "Accessibility access is required",
                   detail: "macOS only lets apps with this permission move and resize other apps' windows.", button: "Grant Access…") {
                _ = Permissions.ensureAccessibility()
            }
        } else if nativeTiling, prefs.snapEnabled, prefs.snapDrag {
            banner(symbol: "rectangle.split.2x1", tint: .orange, title: "macOS edge tiling is also on",
                   detail: "Both react when a window is dragged to a screen edge, so windows can jump.", button: "Turn Off macOS Tiling") {
                NativeTiling.setEnabled(false)
                nativeTiling = NativeTiling.isEnabled
            }
        }
    }

    private func banner(symbol: String, tint: Color, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(button, action: action)
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

enum SnapSettingsActions {
    /// Restarts the monitors and re-registers hotkeys after a snapping preference changed.
    static func apply() {
        SnapController.shared.refresh()
        HotkeyManager.shared.registerAll()
    }
}

// MARK: - Layouts: every position with its shortcut

private struct SnapLayoutsPane: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared

    private let groups: [(String, [AppAction])] = [
        ("Halves", [.snapLeftHalf, .snapRightHalf, .snapTopHalf, .snapBottomHalf]),
        ("Quarters", [.snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight]),
        ("Thirds", [.snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds, .snapRightTwoThirds]),
        ("Size & Displays", [.snapMaximize, .snapCenter, .snapRestore, .snapPreviousDisplay, .snapNextDisplay]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 6) {
                            ForEach(group.1, id: \.rawValue) { row($0) }
                        }
                    }
                }
                Toggle("Pressing a half shortcut again cycles ½ → ⅔ → ⅓", isOn: $prefs.snapCycleSizes)
                HStack {
                    Text("Click a field and press keys. ✕ clears. Maximize pressed twice restores the window.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Snapping Shortcuts") {
                        AppAction.snapActions.forEach { UserDefaults.standard.removeObject(forKey: "hotkey." + $0.rawValue) }
                        SnapSettingsActions.apply()
                    }
                    .controlSize(.small)
                }
            }
            .padding(20)
        }
    }

    private func row(_ action: AppAction) -> some View {
        HStack(spacing: 8) {
            if let position = action.snapPosition { SnapGlyph(position: position) }
            Text(action.title.replacingOccurrences(of: " Quarter", with: "")).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 4)
            if hotkeys.failed.contains(action) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).help("Another app already uses this shortcut.")
            }
            ShortcutRecorder(action: action, revision: hotkeys.revision).frame(width: 112, height: 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Dragging

private struct SnapDraggingPane: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 18) {
                    ZoneDiagram().frame(width: 220, height: 132)
                    VStack(alignment: .leading, spacing: 8) {
                        legend(.blue, "Left / right edge", "Half")
                        legend(.green, "Top edge", "Maximize")
                        legend(.orange, "Corners, edge ends", "Quarter")
                        Text("On an edge shared by two displays, pause for a moment. Press Esc while dragging to cancel.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle("Snap by dragging windows to screen edges and corners", isOn: $prefs.snapDrag)
                    .onChange(of: prefs.snapDrag) { _, _ in SnapSettingsActions.apply() }
                Toggle("Restore the previous size when dragging a snapped window away", isOn: $prefs.snapRestoreOnDrag)
                Toggle("Haptic feedback when a snap target is reached", isOn: $prefs.snapHaptics)
            }
            Section {
                HStack(spacing: 16) {
                    GapPreview(gap: prefs.snapGap).frame(width: 110, height: 66)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gap between windows: \(Int(prefs.snapGap)) pt")
                        Slider(value: $prefs.snapGap, in: 0...40, step: 1)
                        Text("Applies to shortcuts, dragging and custom areas.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func legend(_ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

/// Screen sketch showing which part of each edge triggers which snap.
private struct ZoneDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let t: CGFloat = 9, c = w * 0.16
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5)
                strip(.green, x: c, y: 0, w: w - 2 * c, h: t)
                strip(.blue, x: 0, y: c, w: t, h: h - 2 * c)
                strip(.blue, x: w - t, y: c, w: t, h: h - 2 * c)
                ForEach(0..<4, id: \.self) { i in
                    let left = i % 2 == 0, top = i < 2
                    strip(.orange, x: left ? 0 : w - c, y: top ? 0 : h - t, w: c, h: t)
                    strip(.orange, x: left ? 0 : w - t, y: top ? 0 : h - c, w: t, h: c)
                }
                Image(systemName: "macwindow").font(.system(size: 34)).foregroundStyle(.secondary)
                    .frame(width: w, height: h)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func strip(_ color: Color, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Rectangle().fill(color.opacity(0.85)).frame(width: w, height: h).offset(x: x, y: y)
    }
}

/// Two tiles in a mini screen, spaced by the configured gap (scaled).
private struct GapPreview: View {
    let gap: Double

    var body: some View {
        GeometryReader { geo in
            let g = CGFloat(gap) / 40 * 12
            let tileW = (geo.size.width - g * 3) / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08))
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.8))
                        .frame(width: tileW, height: geo.size.height - g * 2)
                        .offset(x: g + CGFloat(i) * (tileW + g), y: g)
                }
            }
            .animation(.easeOut(duration: 0.12), value: gap)
        }
    }
}

// MARK: - Title bar buttons and modifier gestures

private struct SnapButtonsPane: View {
    @ObservedObject private var prefs = Prefs.shared
    private let colors: [String: Color] = ["Zoom": .green, "Minimize": .yellow, "Close": .red]

    var body: some View {
        Form {
            Section("Title bar buttons") {
                Toggle("Right-click or middle-click a window's buttons to snap it", isOn: $prefs.snapTitlebarButtons)
                    .onChange(of: prefs.snapTitlebarButtons) { _, _ in SnapSettingsActions.apply() }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("Right-click").font(.caption).foregroundStyle(.secondary)
                        Text("Middle-click").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(TitlebarButtonTap.buttons, id: \.key) { button in
                        GridRow {
                            HStack(spacing: 8) {
                                Circle().fill(colors[button.key] ?? .gray).frame(width: 13, height: 13)
                                Text(button.key)
                            }
                            .frame(width: 96, alignment: .leading)
                            TitlebarActionPicker(key: "titlebar\(button.key)Right")
                            TitlebarActionPicker(key: "titlebar\(button.key)Middle")
                        }
                    }
                }
                .disabled(!prefs.snapTitlebarButtons)
            }
            Section {
                modifierPicker("Move the window under the pointer", symbol: "arrow.up.and.down.and.arrow.left.and.right", $prefs.snapMoveModifier)
                modifierPicker("Resize the window under the pointer", symbol: "arrow.up.left.and.arrow.down.right", $prefs.snapResizeModifier)
            } header: {
                Text("Move and resize without clicking")
            } footer: {
                Text("Hold the keys and simply move the pointer over a window.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func modifierPicker(_ title: String, symbol: String, _ selection: Binding<String>) -> some View {
        HStack {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(GestureModifier.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .labelsHidden()
            .frame(width: 110)
            .onChange(of: selection.wrappedValue) { _, _ in SnapSettingsActions.apply() }
        }
    }
}

private struct TitlebarActionPicker: View {
    @AppStorage private var value: String

    init(key: String) {
        _value = AppStorage(wrappedValue: TitlebarButtonTap.defaults[key] ?? "", key)
    }

    var body: some View {
        Picker("", selection: $value) {
            Text("Do nothing").tag("")
            Divider()
            ForEach(SnapPosition.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
        .labelsHidden()
        .frame(width: 180)
    }
}

// MARK: - Custom areas: drawn directly on a miniature screen

private struct SnapAreasPane: View {
    @State private var areas = CustomSnapArea.load()
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draw your own snap targets. While you drag a window they appear as drop zones at the top of the screen.")
                .font(.caption).foregroundStyle(.secondary)
            AreaCanvas(areas: $areas, selection: $selection)
                .aspectRatio(16.0 / 10, contentMode: .fit)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                if let index = areas.firstIndex(where: { $0.id == selection }) {
                    TextField("Name", text: $areas[index].name).textFieldStyle(.roundedBorder).frame(width: 150)
                    Text("\(percent(areas[index].width)) × \(percent(areas[index].height)) at \(percent(areas[index].x)), \(percent(areas[index].y))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        areas.remove(at: index)
                        selection = nil
                    } label: { Image(systemName: "trash") }
                } else {
                    Text(areas.isEmpty ? "No custom areas yet." : "Select an area to rename or delete it. Drag to move, drag its corner to resize.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("From Frontmost Window", action: addFromFrontmostWindow)
                    .help("Uses the position and size of the window behind Settings")
                Button {
                    let area = CustomSnapArea(name: "Area \(areas.count + 1)", x: 0.25, y: 0.2, width: 0.5, height: 0.6)
                    areas.append(area)
                    selection = area.id
                } label: { Label("Add Area", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onChange(of: areas) { _, value in CustomSnapArea.save(value) }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    /// Settings is frontmost right now, so use the topmost window of another app.
    private func addFromFrontmostWindow() {
        guard let info = WindowList.onScreen().first, let screen = NSScreen.screens.first(where: { $0.frame.intersects(info.frame) }) else {
            return Toast.show("No window found")
        }
        let f = SnapGeometry.fractions(of: Geo.flipGlobal(info.frame), in: Geo.flipGlobal(screen.visibleFrame))
        let area = CustomSnapArea(name: info.app.isEmpty ? "Area \(areas.count + 1)" : info.app,
                                  x: Double(f.minX), y: Double(f.minY), width: Double(f.width), height: Double(f.height))
        areas.append(area)
        selection = area.id
    }
}

private struct AreaCanvas: View {
    @Binding var areas: [CustomSnapArea]
    @Binding var selection: UUID?
    /// The area as it was when the current drag began.
    @State private var dragOrigin: CustomSnapArea?

    private static let palette: [Color] = [.blue, .purple, .green, .orange, .pink, .teal]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                grid(size)
                ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                    tile(area, color: AreaCanvas.palette[index % AreaCanvas.palette.count], in: size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = nil }
        }
    }

    private func grid(_ size: CGSize) -> some View {
        Path { path in
            for i in 1..<4 {
                path.move(to: CGPoint(x: size.width * CGFloat(i) / 4, y: 0))
                path.addLine(to: CGPoint(x: size.width * CGFloat(i) / 4, y: size.height))
            }
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        }
        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func tile(_ area: CustomSnapArea, color: Color, in size: CGSize) -> some View {
        let selected = area.id == selection
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(selected ? 0.55 : 0.32))
            RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: selected ? 2.5 : 1)
            Text(area.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Resize handle.
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(color, in: RoundedRectangle(cornerRadius: 5))
                .padding(2)
                .gesture(drag(area, in: size) { origin, dx, dy in
                    var a = origin
                    a.width = AreaCanvas.snap(min(1 - origin.x, max(0.1, origin.width + dx)))
                    a.height = AreaCanvas.snap(min(1 - origin.y, max(0.1, origin.height + dy)))
                    return a
                })
        }
        .frame(width: size.width * area.width, height: size.height * area.height)
        .offset(x: size.width * area.x, y: size.height * area.y)
        .onTapGesture { selection = area.id }
        .gesture(drag(area, in: size) { origin, dx, dy in
            var a = origin
            a.x = AreaCanvas.snap(min(1 - origin.width, max(0, origin.x + dx)))
            a.y = AreaCanvas.snap(min(1 - origin.height, max(0, origin.y + dy)))
            return a
        })
    }

    /// Values land on a 2.5 % grid so areas line up with each other.
    static func snap(_ value: Double) -> Double { (value * 40).rounded() / 40 }

    private func drag(_ area: CustomSnapArea, in size: CGSize, update: @escaping (CustomSnapArea, Double, Double) -> CustomSnapArea) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let origin = dragOrigin ?? area
                if dragOrigin == nil {
                    dragOrigin = area
                    selection = area.id
                }
                let changed = update(origin, Double(value.translation.width / size.width), Double(value.translation.height / size.height))
                if let index = areas.firstIndex(where: { $0.id == area.id }) { areas[index] = changed }
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

// MARK: - Excluded apps

private struct SnapAppsPane: View {
    @ObservedObject private var prefs = Prefs.shared

    private var identifiers: [String] {
        prefs.snapExcluded.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snapwise leaves the windows of these apps alone.").font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(identifiers, id: \.self) { id in
                    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                    HStack(spacing: 10) {
                        Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
                            .resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(url?.deletingPathExtension().lastPathComponent ?? id)
                            Text(id).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { set(identifiers.filter { $0 != id }) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                if identifiers.isEmpty {
                    Text("No excluded apps.").foregroundStyle(.secondary)
                }
            }
            .listStyle(.bordered)
            HStack {
                Spacer()
                Button { addApp() } label: { Label("Add App…", systemImage: "plus") }
            }
        }
        .padding(20)
    }

    private func set(_ ids: [String]) { prefs.snapExcluded = ids.joined(separator: ",") }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        set(Array(NSOrderedSet(array: identifiers + added)) as? [String] ?? identifiers + added)
    }
}
