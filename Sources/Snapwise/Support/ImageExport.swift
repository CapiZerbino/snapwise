import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable {
    case png, jpg, heic

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        case .heic: return .heic
        }
    }
}

extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }

    /// Encodes the image; `scale` is written as DPI so Retina captures open at their on-screen point size.
    func encoded(as format: ImageFormat, quality: Double = 0.9, scale: CGFloat = 1) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else { return nil }
        let dpi = 72.0 * Double(scale)
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(dest, self, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    func nsImage(scale: CGFloat) -> NSImage {
        NSImage(cgImage: self, size: CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale))
    }

    func resized(to newSize: CGSize) -> CGImage? {
        let w = max(1, Int(newSize.width.rounded())), h = max(1, Int(newSize.height.rounded()))
        guard let ctx = CGContext.bitmap(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

extension CGContext {
    /// sRGB premultiplied RGBA bitmap context.
    static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Draws an image upright inside a context whose y axis points down.
    func drawFlipped(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }
}

extension NSImage {
    /// Full-resolution pixels. `cgImage(forProposedRect:)` alone would hand back the point-sized
    /// rendition of a Retina image, silently halving its resolution.
    var cgImage: CGImage? {
        let bitmaps = representations.compactMap { $0 as? NSBitmapImageRep }
        if let largest = bitmaps.max(by: { $0.pixelsWide < $1.pixelsWide })?.cgImage { return largest }
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// Expands `{date}`, `{time}`, `{kind}` tokens in the user's filename pattern.
enum FilenameTemplate {
    static func render(_ pattern: String, date: Date, kind: String, timeZone: TimeZone = .current) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd"
        let day = df.string(from: date)
        df.dateFormat = "HH.mm.ss"
        let time = df.string(from: date)
        var name = pattern.isEmpty ? "Snapwise {date} at {time}" : pattern
        name = name.replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{kind}", with: kind)
        // Path separators would silently create folders or fail the write.
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
    }

    /// Returns a URL in `folder` that does not collide with an existing file.
    static func uniqueURL(folder: URL, name: String, ext: String) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}

enum Output {
    static func copy(image: CGImage, scale: CGFloat) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image.nsImage(scale: scale)])
    }

    static func copy(fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
    }

    static func copy(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Writes a screenshot to the user's save folder using their format and filename preferences.
    @discardableResult
    static func save(image: CGImage, scale: CGFloat, to explicitURL: URL? = nil) -> URL? {
        let prefs = Prefs.shared
        let format = ImageFormat(rawValue: prefs.imageFormat) ?? .png
        let url = explicitURL ?? destinationURL(kind: "Screenshot", ext: format.rawValue)
        let target = ImageFormat(rawValue: url.pathExtension.lowercased()) ?? format
        guard let data = image.encoded(as: target, quality: prefs.jpegQuality, scale: scale) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Toast.show("Could not save: \(error.localizedDescription)")
            return nil
        }
    }

    /// Copies a recording out of history into the user's save folder.
    @discardableResult
    static func save(fileAt source: URL, kind: String) -> URL? {
        let url = destinationURL(kind: kind, ext: source.pathExtension)
        do {
            try FileManager.default.copyItem(at: source, to: url)
            return url
        } catch {
            Toast.show("Could not save: \(error.localizedDescription)")
            return nil
        }
    }

    static func destinationURL(kind: String, ext: String) -> URL {
        let prefs = Prefs.shared
        let folder = prefs.saveFolderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = FilenameTemplate.render(prefs.filenamePattern, date: Date(), kind: kind)
        return FilenameTemplate.uniqueURL(folder: folder, name: name, ext: ext)
    }

    static func playShutter() {
        guard Prefs.shared.playSounds else { return }
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        (NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink"))?.play()
    }
}
