import AppKit

/// The Actions wheel: things done with files rather than to them. These work on any file or folder.
enum FileActions {
    static func perform(_ action: FileAction, on urls: [URL]) {
        switch action {
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                return Toast.show("AirDrop is not available")
            }
            NSApp.activate()
            service.perform(withItems: urls)
        case .float:
            let images = urls.compactMap { try? ImageConversions.load($0) }
            guard !images.isEmpty else { return Toast.show("Only images can float") }
            images.prefix(8).forEach { PinWindowController.pin(image: $0, scale: 1) }
        case .copy:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            Toast.show(urls.count == 1 ? "Copied \(urls[0].lastPathComponent)" : "Copied \(urls.count) items")
        case .move:
            move(urls)
        case .copyPath:
            Output.copy(text: urls.map(\.path).joined(separator: "\n"))
            Toast.show(urls.count == 1 ? "Copied path" : "Copied \(urls.count) paths")
        case .terminal:
            // A folder opens itself; a file opens the folder it is in.
            let folder = urls[0].hasDirectoryPath ? urls[0] : urls[0].deletingLastPathComponent()
            let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
                ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func move(_ urls: [URL]) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = urls.count == 1 ? "Move \(urls[0].lastPathComponent) to…" : "Move \(urls.count) items to…"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var moved = 0
        for url in urls where url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
            let ext = url.pathExtension
            let target = ConversionCatalog.freeURL(in: folder, base: url.deletingPathExtension().lastPathComponent, ext: ext,
                                                   isDirectory: url.hasDirectoryPath && ext.isEmpty)
            do {
                try FileManager.default.moveItem(at: url, to: target)
                moved += 1
            } catch {
                return Toast.show("Could not move \(url.lastPathComponent): \(error.localizedDescription)", duration: 3.5)
            }
        }
        Toast.show(moved == 1 ? "Moved to \(folder.lastPathComponent)" : "Moved \(moved) items to \(folder.lastPathComponent)")
    }
}
