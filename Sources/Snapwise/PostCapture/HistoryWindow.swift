import AppKit
import SwiftUI

enum HistoryWindowController {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            window = WindowFactory.make(title: "Capture History", size: CGSize(width: 820, height: 560)) {
                HistoryView(store: .shared)
            }
        }
        if let window { WindowFactory.present(window) }
    }
}

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var filter: CaptureKind?

    private var visible: [CaptureItem] { store.items.filter { filter == nil || $0.kind == filter } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $filter) {
                    Text("All").tag(CaptureKind?.none)
                    Text("Screenshots").tag(CaptureKind?.some(.screenshot))
                    Text("Recordings").tag(CaptureKind?.some(.video))
                    Text("GIFs").tag(CaptureKind?.some(.gif))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
                Spacer()
                Text("\(visible.count) items").foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            if visible.isEmpty {
                ContentUnavailableView("No captures yet", systemImage: "camera.viewfinder",
                                       description: Text("Screenshots and recordings appear here."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        ForEach(visible) { HistoryCell(item: $0, store: store) }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

private struct HistoryCell: View {
    let item: CaptureItem
    let store: HistoryStore
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor))
                if let thumbnail = store.thumbnail(for: item) {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).padding(6)
                }
                if hovering {
                    RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.45))
                    HStack(spacing: 8) {
                        action("doc.on.doc", "Copy") { ItemActions.copy(item) }
                        action("square.and.arrow.down", "Save") { ItemActions.save(item) }
                        action("pencil", "Edit") { ItemActions.edit(item) }
                        action("trash", "Delete") { delete() }
                    }
                }
            }
            .frame(height: 120)
            .onHover { hovering = $0 }
            .onTapGesture { QuickAccessManager.shared.show(item) }
            .help("Click to restore to the overlay")
            Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            Text("\(item.kind.label) · \(item.infoText)").font(.caption2).foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Restore to Overlay") { QuickAccessManager.shared.show(item) }
            Button("Show in Finder") { ItemActions.reveal(item) }
            if item.kind == .screenshot { Button("Pin to Screen") { ItemActions.pin(item) } }
            Divider()
            Button("Delete") { delete() }
        }
    }

    private func delete() {
        QuickAccessManager.shared.close(item, remember: false)
        store.delete(item)
    }

    private func action(_ symbol: String, _ help: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).foregroundStyle(.white).frame(width: 30, height: 30).background(.black.opacity(0.6), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
