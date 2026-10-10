import AppKit
import SwiftUI

/// Operations on a stored capture, shared by the quick access overlay and the history window.
enum ItemActions {
    static func copy(_ item: CaptureItem) {
        if let image = item.cgImage {
            Output.copy(image: image, scale: item.scale)
        } else {
            Output.copy(fileURL: stagedURL(for: item) ?? item.url)
        }
        Toast.show("Copied")
    }

    static func save(_ item: CaptureItem) {
        let url: URL?
        if let image = item.cgImage {
            url = Output.save(image: image, scale: item.scale)
        } else {
            url = Output.save(fileAt: item.url, kind: item.kind.label)
        }
        if let url { Toast.show("Saved to \(url.lastPathComponent)") }
    }

    static func edit(_ item: CaptureItem) {
        switch item.kind {
        case .screenshot: EditorWindowController.open(item: item)
        case .video: VideoEditorWindowController.open(url: item.url, clicksURL: item.clicksURL)
        case .gif: NSWorkspace.shared.open(item.url)
        }
    }

    static func pin(_ item: CaptureItem) {
        guard let image = item.cgImage else { return }
        PinWindowController.pin(image: image, scale: item.scale)
    }

    static func reveal(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    static func copyText(_ item: CaptureItem) {
        guard let image = item.cgImage else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let text = TextRecognizer.recognize(image)
            DispatchQueue.main.async {
                if text.isEmpty { Toast.show("No text found") } else {
                    Output.copy(text: text)
                    Toast.show("Copied text")
                }
            }
        }
    }

    /// A copy of the capture with a human-readable name and the user's image format,
    /// suitable for dragging into other apps or sharing.
    static func stagedURL(for item: CaptureItem) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Snapwise-export/\(item.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = FilenameTemplate.render(Prefs.shared.filenamePattern, date: item.date, kind: item.kind.label)
        if let image = item.cgImage {
            let format = ImageFormat(rawValue: Prefs.shared.imageFormat) ?? .png
            let url = folder.appendingPathComponent(name).appendingPathExtension(format.rawValue)
            guard let data = image.encoded(as: format, quality: Prefs.shared.jpegQuality, scale: item.scale) else { return nil }
            try? data.write(to: url, options: .atomic)
            return url
        }
        let url = folder.appendingPathComponent(name).appendingPathExtension(item.url.pathExtension)
        if !FileManager.default.fileExists(atPath: url.path) {
            // A hard link avoids duplicating large recordings.
            if (try? FileManager.default.linkItem(at: item.url, to: url)) == nil {
                try? FileManager.default.copyItem(at: item.url, to: url)
            }
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

enum WindowFactory {
    /// Standard titled window hosting a SwiftUI view; brought forward even though the app is a menu-bar agent.
    static func make<V: View>(title: String, size: CGSize, resizable: Bool = true, @ViewBuilder content: () -> V) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.setContentSize(size)
        window.center()
        return window
    }

    static func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
