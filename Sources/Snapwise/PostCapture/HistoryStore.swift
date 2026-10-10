import AppKit
import AVFoundation

enum CaptureKind: String, Codable, CaseIterable {
    case screenshot, video, gif

    var label: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .video: return "Recording"
        case .gif: return "GIF"
        }
    }
}

/// One capture kept in history. Screenshots are always stored as PNG; the user's format applies on export.
struct CaptureItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: CaptureKind
    var fileName: String
    var date: Date
    var width: Int
    var height: Int
    var scale: CGFloat

    var url: URL { HistoryStore.shared.directory.appendingPathComponent(fileName) }
    /// Click timeline recorded alongside a video; drives auto-zoom in the video editor.
    var clicksURL: URL { url.deletingPathExtension().appendingPathExtension("clicks.json") }

    var cgImage: CGImage? {
        guard kind == .screenshot, let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    var fileSizeText: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes ?? 0), countStyle: .file)
    }

    var infoText: String { "\(width) × \(height) · \(fileSizeText)" }
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    let directory: URL
    @Published private(set) var items: [CaptureItem] = []
    private var thumbnails = NSCache<NSString, NSImage>()
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapwise/History", isDirectory: true)
        self.directory = base
        // Carry captures over from the app's former name.
        if directory == nil, !FileManager.default.fileExists(atPath: base.path) {
            let legacy = base.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Lumshot/History")
            if FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.moveItem(at: legacy, to: base)
            }
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([CaptureItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: base.appendingPathComponent($0.fileName).path) }
        }
    }

    @discardableResult
    func add(image: CGImage, scale: CGFloat) -> CaptureItem? {
        let id = UUID()
        let item = CaptureItem(id: id, kind: .screenshot, fileName: "\(id.uuidString).png", date: Date(),
                               width: image.width, height: image.height, scale: scale)
        guard let data = image.encoded(as: .png, scale: scale),
              (try? data.write(to: directory.appendingPathComponent(item.fileName), options: .atomic)) != nil else { return nil }
        insert(item)
        return item
    }

    /// Moves a finished recording into history.
    @discardableResult
    func add(fileAt source: URL, kind: CaptureKind, pixelSize: CGSize, scale: CGFloat) -> CaptureItem? {
        let id = UUID()
        let item = CaptureItem(id: id, kind: kind, fileName: "\(id.uuidString).\(source.pathExtension)", date: Date(),
                               width: Int(pixelSize.width), height: Int(pixelSize.height), scale: scale)
        do {
            try FileManager.default.moveItem(at: source, to: directory.appendingPathComponent(item.fileName))
        } catch {
            return nil
        }
        insert(item)
        return item
    }

    /// Replaces a screenshot's pixels after it was edited.
    func update(_ item: CaptureItem, image: CGImage) -> CaptureItem {
        // The item may have been deleted while its editor was open.
        guard items.contains(where: { $0.id == item.id }) else { return item }
        var updated = item
        updated.width = image.width
        updated.height = image.height
        if let data = image.encoded(as: .png, scale: item.scale) {
            try? data.write(to: directory.appendingPathComponent(item.fileName), options: .atomic)
        }
        thumbnails.removeObject(forKey: item.id.uuidString as NSString)
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = updated }
        persist()
        return updated
    }

    func delete(_ item: CaptureItem) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName)
            .deletingPathExtension().appendingPathExtension("clicks.json"))
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.forEach(delete)
        thumbnails.removeAllObjects()
    }

    func purgeExpired(now: Date = Date(), retentionDays: Int = Prefs.shared.historyRetentionDays) {
        guard retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        items.filter { $0.date < cutoff }.forEach(delete)
    }

    func thumbnail(for item: CaptureItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let fileURL = directory.appendingPathComponent(item.fileName)
        var image: NSImage?
        if item.kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) { image = NSImage(cgImage: cg, size: .zero) }
        } else if let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceThumbnailMaxPixelSize: 640,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) { image = NSImage(cgImage: cg, size: .zero) }
        }
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    private func insert(_ item: CaptureItem) {
        items.insert(item, at: 0)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }
}
