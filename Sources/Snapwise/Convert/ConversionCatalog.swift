import AppKit
import UniformTypeIdentifiers

/// The three wheels: convert to another format, run a tool on the file, or do something with it.
enum WheelKind: String, CaseIterable {
    case convert, tools, actions

    var title: String {
        switch self {
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }

    var symbol: String {
        switch self {
        case .convert: return "arrow.triangle.2.circlepath"
        case .tools: return "wrench.and.screwdriver"
        case .actions: return "square.and.arrow.up.on.square"
        }
    }

    /// The modifier that opens this wheel while a file is being dragged (configurable).
    var trigger: WheelTrigger {
        let stored: String
        switch self {
        case .convert: stored = Prefs.shared.convertKeyConvert
        case .tools: stored = Prefs.shared.convertKeyTools
        case .actions: stored = Prefs.shared.convertKeyActions
        }
        return WheelTrigger(rawValue: stored) ?? .shift
    }

    static func kind(for trigger: WheelTrigger) -> WheelKind? { allCases.first { $0.trigger == trigger } }
}

/// A single modifier key that is tapped (pressed and released on its own) to open a wheel.
enum WheelTrigger: String, CaseIterable {
    case shift, command, control, option

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .command: return .command
        case .control: return .control
        case .option: return .option
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        }
    }

    var label: String { "\(symbol) \(rawValue.capitalized)" }

    /// The trigger when exactly one of the four modifiers is held, nil for none or a combination.
    static func only(in flags: NSEvent.ModifierFlags) -> WheelTrigger? {
        let held = allCases.filter { flags.contains($0.flag) }
        return held.count == 1 ? held[0] : nil
    }
}

/// What a file is, as far as conversions are concerned.
enum FileFamily: Hashable {
    case image, video, audio, pdf, document, table, archive, folder, other

    static func of(_ url: URL) -> FileFamily {
        if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            // Packages such as .rtfd are documents, not folders to zip.
            if url.pathExtension.lowercased() == "rtfd" { return .document }
            return .folder
        }
        let ext = url.pathExtension.lowercased()
        if ["csv", "tsv"].contains(ext) { return .table }
        if ["md", "markdown"].contains(ext) { return .document }
        if ["zip", "tar", "gz", "tgz"].contains(ext) { return .archive }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .rtf) || type.conforms(to: .html) || type.conforms(to: .plainText) || type.conforms(to: .rtfd)
            || ["docx", "doc", "odt", "webarchive"].contains(ext) { return .document }
        return .other
    }
}

enum FileTool: String, CaseIterable {
    case compressImage, resizeHalf, rotate, flip, stripMetadata, removeBackground, copyText, annotate, combineIntoPDF
    case compressVideo, downscale720, mute, extractFrame, editVideo
    case mergePDFs, splitPDF, rotatePDF, compressPDF, copyPDFText
    case extract, zip, tarGz
}

enum FileAction: String, CaseIterable {
    case airDrop, float, copy, move, copyPath, terminal
}

/// One bubble on a wheel.
enum FileOperation: Hashable {
    /// Convert each file to the format with this file extension.
    case convert(String)
    case tool(FileTool)
    case action(FileAction)

    /// Short text inside the bubble.
    var label: String {
        switch self {
        case .convert(let ext): return ext.uppercased()
        case .tool(let tool):
            switch tool {
            case .compressImage, .compressVideo, .compressPDF: return "Compress"
            case .resizeHalf: return "50 %"
            case .rotate, .rotatePDF: return "Rotate"
            case .flip: return "Flip"
            case .stripMetadata: return "No EXIF"
            case .removeBackground: return "Cut Out"
            case .copyText, .copyPDFText: return "Text"
            case .annotate: return "Annotate"
            case .combineIntoPDF: return "To PDF"
            case .downscale720: return "720p"
            case .mute: return "Mute"
            case .extractFrame: return "Frame"
            case .editVideo: return "Trim"
            case .mergePDFs: return "Merge"
            case .splitPDF: return "Split"
            case .extract: return "Extract"
            case .zip: return "ZIP"
            case .tarGz: return "TAR.GZ"
            }
        case .action(let action):
            switch action {
            case .airDrop: return "AirDrop"
            case .float: return "Float"
            case .copy: return "Copy"
            case .move: return "Move"
            case .copyPath: return "Path"
            case .terminal: return "Terminal"
            }
        }
    }

    /// Full description shown in the wheel's centre while the bubble is targeted.
    var title: String {
        switch self {
        case .convert(let ext): return "Convert to \(ext.uppercased())"
        case .tool(let tool):
            switch tool {
            case .compressImage: return "Compress image"
            case .resizeHalf: return "Resize to 50 %"
            case .rotate: return "Rotate 90° clockwise"
            case .flip: return "Flip horizontally"
            case .stripMetadata: return "Remove metadata"
            case .removeBackground: return "Remove background"
            case .copyText: return "Copy text (OCR)"
            case .annotate: return "Open in Annotate"
            case .combineIntoPDF: return "Combine into one PDF"
            case .compressVideo: return "Compress video (HEVC)"
            case .downscale720: return "Downscale to 720p"
            case .mute: return "Remove audio"
            case .extractFrame: return "Save first frame as PNG"
            case .editVideo: return "Trim in the video editor"
            case .mergePDFs: return "Merge PDFs"
            case .splitPDF: return "Split into pages"
            case .rotatePDF: return "Rotate pages 90°"
            case .compressPDF: return "Compress PDF"
            case .copyPDFText: return "Copy text"
            case .extract: return "Extract archive"
            case .zip: return "Compress to ZIP"
            case .tarGz: return "Compress to TAR.GZ"
            }
        case .action(let action):
            switch action {
            case .airDrop: return "Send with AirDrop"
            case .float: return "Float on screen"
            case .copy: return "Copy to clipboard"
            case .move: return "Move to folder…"
            case .copyPath: return "Copy path"
            case .terminal: return "Open in Terminal"
            }
        }
    }

    var symbol: String {
        switch self {
        case .convert: return "doc.badge.arrow.up"
        case .tool(let tool):
            switch tool {
            case .compressImage, .compressVideo, .compressPDF: return "arrow.down.right.and.arrow.up.left"
            case .resizeHalf, .downscale720: return "arrow.down.left.and.arrow.up.right.square"
            case .rotate, .rotatePDF: return "rotate.right"
            case .flip: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
            case .stripMetadata: return "location.slash"
            case .removeBackground: return "person.crop.rectangle"
            case .copyText, .copyPDFText: return "text.viewfinder"
            case .annotate: return "pencil.tip.crop.circle"
            case .combineIntoPDF, .mergePDFs: return "doc.on.doc"
            case .mute: return "speaker.slash"
            case .extractFrame: return "photo"
            case .editVideo: return "scissors"
            case .splitPDF: return "square.split.2x1"
            case .extract: return "shippingbox.and.arrow.backward"
            case .zip, .tarGz: return "archivebox"
            }
        case .action(let action):
            switch action {
            case .airDrop: return "airplayaudio"
            case .float: return "pin"
            case .copy: return "doc.on.clipboard"
            case .move: return "folder"
            case .copyPath: return "link"
            case .terminal: return "terminal"
            }
        }
    }
}

enum ConversionCatalog {
    /// Formats each family converts to. Every one is written with macOS frameworks, so nothing leaves the Mac.
    static let targets: [FileFamily: [String]] = [
        .image: ["png", "jpg", "heic", "avif", "tiff", "gif", "bmp", "pdf", "ico", "icns"],
        .video: ["mp4", "mov", "m4a", "gif"],
        .audio: ["m4a", "wav", "aiff", "flac", "caf"],
        .pdf: ["png", "jpg", "txt", "rtf"],
        .document: ["docx", "pdf", "rtf", "html", "txt", "odt"],
        .table: ["csv", "tsv", "html"],
    ]

    /// The family shared by every file, or nil for a mixed selection.
    static func family(of urls: [URL]) -> FileFamily? {
        let families = Set(urls.map(FileFamily.of))
        return families.count == 1 ? families.first : nil
    }

    static func operations(for urls: [URL], kind: WheelKind) -> [FileOperation] {
        guard !urls.isEmpty else { return [] }
        let family = family(of: urls)
        let single = urls.count == 1
        switch kind {
        case .convert:
            guard let family, let formats = targets[family] else { return [] }
            // Converting a file to its own format is pointless; ".jpeg" counts as JPG and ".tif" as TIFF.
            let own = Set(urls.map { normalized($0.pathExtension) })
            return formats.filter { !(own.count == 1 && own.contains($0)) }.map { .convert($0) }
        case .tools:
            var tools: [FileTool]
            switch family {
            case .image:
                tools = [.compressImage, .resizeHalf, .rotate, .flip, .stripMetadata, .removeBackground, .copyText]
                tools += single ? [.annotate] : [.combineIntoPDF]
            case .video: tools = [.compressVideo, .downscale720, .mute, .extractFrame] + (single ? [.editVideo] : [])
            case .pdf: tools = (single ? [] : [.mergePDFs]) + [.splitPDF, .rotatePDF, .compressPDF, .copyPDFText]
            case .archive: tools = [.extract]
            default: tools = []
            }
            return (tools + [.zip, .tarGz]).map { .tool($0) }
        case .actions:
            let actions = FileAction.allCases.filter { $0 != .float || family == .image }
            return actions.map { .action($0) }
        }
    }

    /// Canonical spelling of a file extension.
    static func normalized(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg", "jpe": return "jpg"
        case "tif": return "tiff"
        case "aif", "aifc": return "aiff"
        case "htm": return "html"
        default: return ext.lowercased()
        }
    }

    /// `folder/base.ext`, or `folder/base 2.ext`, `base 3.ext`… so existing files are never overwritten.
    static func freeURL(in folder: URL, base: String, ext: String, isDirectory: Bool = false, fileManager: FileManager = .default) -> URL {
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? base : "\(base) \(n)"
            return isDirectory || ext.isEmpty ? folder.appendingPathComponent(name, isDirectory: isDirectory)
                : folder.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var n = 1
        while fileManager.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }

    /// Where the result for `source` goes: beside it, named after it, with an optional suffix such as "(compressed)".
    static func output(for source: URL, ext: String, suffix: String? = nil) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + (suffix.map { " (\($0))" } ?? "")
        return freeURL(in: source.deletingLastPathComponent(), base: base, ext: ext)
    }
}
