import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns one annotation window. Edits are written back to the history item when the window closes.
final class EditorWindowController: NSObject, NSWindowDelegate {
    private static var open: [EditorWindowController] = []

    private let model: EditorModel
    private var item: CaptureItem?
    private var window: NSWindow!

    static func open(item: CaptureItem) {
        if let existing = open.first(where: { $0.item?.id == item.id }) { return WindowFactory.present(existing.window) }
        guard let image = item.cgImage else { return Toast.show("Could not open the capture") }
        present(EditorWindowController(model: EditorModel(image: image, scale: item.scale), item: item))
    }

    static func open(projectAt url: URL) {
        do {
            present(EditorWindowController(model: try ProjectFile.read(from: url), item: nil))
        } catch {
            Toast.show("Could not open project: \(error.localizedDescription)")
        }
    }

    private static func present(_ controller: EditorWindowController) {
        open.append(controller)
        WindowFactory.present(controller.window)
    }

    private init(model: EditorModel, item: CaptureItem?) {
        self.model = model
        self.item = item
        super.init()
        var actions = EditorActions()
        actions.copy = { [weak self] in self?.copy() }
        actions.save = { [weak self] in self?.save() }
        actions.saveAs = { [weak self] in self?.saveAs() }
        actions.saveProject = { [weak self] in _ = self?.saveProject() }
        actions.done = { [weak self] in self?.window.performClose(nil) }
        actions.pin = { [weak self] in self?.pin() }
        actions.share = { [weak self] in self?.share() }
        actions.resize = { [weak self] in self?.promptResize() }
        actions.dragURL = { [weak self] in self?.temporaryExportURL() }
        model.onSave = actions.save
        model.onCopy = actions.copy

        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame.size
        let natural = CGSize(width: model.state.size.width / model.scale + 80, height: model.state.size.height / model.scale + 150)
        let size = CGSize(width: min(max(natural.width, 980), visible.width * 0.88), height: min(max(natural.height, 620), visible.height * 0.88))
        window = WindowFactory.make(title: "Annotate", size: size) { EditorRootView(model: model, actions: actions) }
        window.delegate = self
    }

    /// Project documents have no history entry to fall back on, so unsaved edits need a decision.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.commitPendingEdits?()
        guard model.isDirty, item == nil else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to this project?"
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveProject()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        commitToHistory()
        EditorWindowController.open.removeAll { $0 === self }
    }

    /// Keeps the history entry and its overlay card in sync with the edited image.
    private func commitToHistory() {
        guard model.isDirty, let current = item else { return }
        let updated = HistoryStore.shared.update(current, image: model.exported())
        item = updated
        model.markSaved()
        QuickAccessManager.shared.refresh(updated)
    }

    private func copy() {
        Output.copy(image: model.exported(), scale: model.scale)
        Toast.show("Copied")
    }

    private func save() {
        commitToHistory()
        if let url = Output.save(image: model.exported(), scale: model.scale) { Toast.show("Saved to \(url.lastPathComponent)") }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.nameFieldStringValue = FilenameTemplate.render(Prefs.shared.filenamePattern, date: Date(), kind: "Screenshot") + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Output.save(image: model.exported(), scale: model.scale, to: url)
    }

    /// Returns true once the project is on disk.
    @discardableResult
    private func saveProject() -> Bool {
        model.commitPendingEdits?()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectFile.fileExtension) ?? .json]
        panel.nameFieldStringValue = "Untitled." + ProjectFile.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try ProjectFile.write(model, to: url)
            if item == nil { model.markSaved() }
            return true
        } catch {
            Toast.show("Could not save project: \(error.localizedDescription)")
            return false
        }
    }

    private func pin() {
        PinWindowController.pin(image: model.exported(), scale: model.scale)
    }

    private func temporaryExportURL() -> URL? {
        let format = ImageFormat(rawValue: Prefs.shared.imageFormat) ?? .png
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Snapwise-export/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = FilenameTemplate.render(Prefs.shared.filenamePattern, date: Date(), kind: "Screenshot")
        let url = folder.appendingPathComponent(name).appendingPathExtension(format.rawValue)
        guard let data = model.exported().encoded(as: format, quality: Prefs.shared.jpegQuality, scale: model.scale),
              (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private func share() {
        guard let url = temporaryExportURL(), let view = window.contentView else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: CGRect(x: view.bounds.maxX - 120, y: view.bounds.maxY - 36, width: 1, height: 1),
                                                  of: view, preferredEdge: .minY)
    }

    private func promptResize() {
        let alert = NSAlert()
        alert.messageText = "Resize image"
        alert.informativeText = "New width in pixels (height follows the aspect ratio). Annotations are flattened."
        let field = NSTextField(string: "\(Int(model.state.size.width))")
        field.frame = CGRect(x: 0, y: 0, width: 160, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Resize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let width = Double(field.stringValue), width >= 1, width <= 20_000 else { return }
        model.resize(toWidth: CGFloat(width))
    }
}
