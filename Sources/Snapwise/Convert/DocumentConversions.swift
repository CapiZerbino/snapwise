import AppKit
import PDFKit

/// Text documents (AppKit's text system), PDFs (PDFKit), CSV/TSV tables and archives (system ditto/tar).
enum DocumentConversions {
    enum Failure: LocalizedError {
        case unreadable(String), failed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Could not read \(name)"
            case .failed(let what): return what
            }
        }
    }

    // MARK: - Text documents

    static func convert(document url: URL, to ext: String) throws -> URL {
        let text = try attributedString(from: url)
        let output = ConversionCatalog.output(for: url, ext: ext)
        let range = NSRange(location: 0, length: text.length)
        switch ext {
        case "txt":
            try text.string.write(to: output, atomically: true, encoding: .utf8)
        case "pdf":
            try writePDF(text, to: output)
        default:
            let types: [String: NSAttributedString.DocumentType] = ["docx": .officeOpenXML, "rtf": .rtf, "html": .html, "odt": .openDocument]
            guard let type = types[ext] else { throw Failure.failed("Unsupported format \(ext)") }
            let data = try text.data(from: range, documentAttributes: [.documentType: type])
            try data.write(to: output, options: .atomic)
        }
        return output
    }

    static func attributedString(from url: URL) throws -> NSAttributedString {
        if ["md", "markdown"].contains(url.pathExtension.lowercased()) {
            let source = try String(contentsOf: url, encoding: .utf8)
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            return NSAttributedString((try? AttributedString(markdown: source, options: options)) ?? AttributedString(source))
        }
        // HTML and web archives are parsed by WebKit, which only runs on the main thread.
        let read = { try? NSAttributedString(url: url, options: [:], documentAttributes: nil) }
        let needsMain = ["html", "htm", "webarchive"].contains(url.pathExtension.lowercased()) && !Thread.isMainThread
        guard let text = needsMain ? DispatchQueue.main.sync(execute: read) : read() else { throw Failure.unreadable(url.lastPathComponent) }
        return text
    }

    /// Lays the text out on US Letter / A4 pages (from the default print settings) through the print system.
    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var thrown: Error?
        let work = {
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            info.isVerticallyCentered = false
            let width = info.paperSize.width - info.leftMargin - info.rightMargin
            let view = NSTextView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
            view.textStorage?.setAttributedString(text)
            view.sizeToFit()
            let operation = NSPrintOperation(view: view, printInfo: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            if !operation.run() { thrown = Failure.failed("Could not create the PDF") }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        if let thrown { throw thrown }
    }

    // MARK: - PDF

    static func convert(pdf url: URL, to ext: String) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable(url.lastPathComponent) }
        switch ext {
        case "txt":
            let output = ConversionCatalog.output(for: url, ext: "txt")
            try (document.string ?? "").write(to: output, atomically: true, encoding: .utf8)
            return output
        case "rtf":
            let text = NSMutableAttributedString()
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.attributedString { text.append(page) }
                text.append(NSAttributedString(string: "\n\u{0C}"))
            }
            let output = ConversionCatalog.output(for: url, ext: "rtf")
            try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                .write(to: output, options: .atomic)
            return output
        default:
            // One image per page at 300 DPI; several pages go into a folder named after the PDF.
            let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
            let folder = pages.count > 1
                ? ConversionCatalog.freeURL(in: url.deletingLastPathComponent(), base: url.deletingPathExtension().lastPathComponent + " (\(ext.uppercased()))", ext: "", isDirectory: true)
                : url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = url.deletingPathExtension().lastPathComponent
            for (index, page) in pages.enumerated() {
                guard let image = render(page, dpi: 300) else { throw Failure.failed("Could not render page \(index + 1)") }
                let output = pages.count > 1 ? ConversionCatalog.freeURL(in: folder, base: "\(base) \(index + 1)", ext: ext)
                    : ConversionCatalog.output(for: url, ext: ext)
                try ImageConversions.write(image, to: output, ext: ext)
                if pages.count == 1 { return output }
            }
            return folder
        }
    }

    static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        // Capped so a poster-sized page does not need gigabytes of memory.
        let scale = min(dpi / 72, 12_000 / max(box.width, box.height))
        let size = CGSize(width: (box.width * scale).rounded(), height: (box.height * scale).rounded())
        let image = page.thumbnail(of: size, for: .mediaBox)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func run(_ tool: FileTool, on urls: [URL]) throws -> [URL] {
        let documents = try urls.map { url -> PDFDocument in
            guard let document = PDFDocument(url: url) else { throw Failure.unreadable(url.lastPathComponent) }
            return document
        }
        switch tool {
        case .mergePDFs:
            let merged = PDFDocument()
            for document in documents {
                for index in 0..<document.pageCount { if let page = document.page(at: index) { merged.insert(page, at: merged.pageCount) } }
            }
            let output = ConversionCatalog.freeURL(in: urls[0].deletingLastPathComponent(), base: "Merged", ext: "pdf")
            guard merged.write(to: output) else { throw Failure.failed("Could not write the merged PDF") }
            return [output]
        case .splitPDF:
            return try zip(urls, documents).map { url, document in
                let folder = ConversionCatalog.freeURL(in: url.deletingLastPathComponent(), base: url.deletingPathExtension().lastPathComponent + " (pages)",
                                                       ext: "", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for index in 0..<document.pageCount {
                    let single = PDFDocument()
                    if let page = document.page(at: index) { single.insert(page, at: 0) }
                    single.write(to: ConversionCatalog.freeURL(in: folder, base: "\(url.deletingPathExtension().lastPathComponent) \(index + 1)", ext: "pdf"))
                }
                return folder
            }
        case .rotatePDF:
            return try zip(urls, documents).map { url, document in
                for index in 0..<document.pageCount { document.page(at: index).map { $0.rotation = ($0.rotation + 90) % 360 } }
                let output = ConversionCatalog.output(for: url, ext: "pdf", suffix: "rotated")
                guard document.write(to: output) else { throw Failure.failed("Could not write the PDF") }
                return output
            }
        case .compressPDF:
            return try zip(urls, documents).map { url, document in
                let output = ConversionCatalog.output(for: url, ext: "pdf", suffix: "compressed")
                let options: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
                guard document.write(to: output, withOptions: options) else { throw Failure.failed("Could not write the PDF") }
                return output
            }
        default:
            return []
        }
    }

    // MARK: - Tables

    static func convert(table url: URL, to ext: String) throws -> URL {
        let source = try String(contentsOf: url, encoding: .utf8)
        let rows = DelimitedText.parse(source, separator: url.pathExtension.lowercased() == "tsv" ? "\t" : ",")
        let output = ConversionCatalog.output(for: url, ext: ext)
        let text: String
        switch ext {
        case "tsv": text = DelimitedText.format(rows, separator: "\t")
        case "csv": text = DelimitedText.format(rows, separator: ",")
        default: text = DelimitedText.html(rows, title: url.deletingPathExtension().lastPathComponent)
        }
        try text.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    // MARK: - Archives

    static func archive(_ urls: [URL], tarGz: Bool) throws -> URL {
        let folder = urls[0].deletingLastPathComponent()
        let base = urls.count == 1 ? urls[0].lastPathComponent : "Archive"
        let output = ConversionCatalog.freeURL(in: folder, base: base, ext: tarGz ? "tar.gz" : "zip")
        if tarGz {
            // Names relative to the folder of the first item, so the archive holds just these items.
            try shell("/usr/bin/tar", ["-czf", output.path, "-C", folder.path] + urls.map(\.lastPathComponent))
        } else if urls.count == 1 {
            try shell("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, output.path])
        } else {
            try shell("/usr/bin/zip", ["-r", "-q", "-y", output.path] + urls.map(\.lastPathComponent), in: folder)
        }
        return output
    }

    static func extract(_ url: URL) throws -> URL {
        let name = url.lastPathComponent
        var base = url.deletingPathExtension().lastPathComponent
        if base.lowercased().hasSuffix(".tar") { base = String(base.dropLast(4)) }
        let folder = ConversionCatalog.freeURL(in: url.deletingLastPathComponent(), base: base, ext: "", isDirectory: true)
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            try shell("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
        } else if ext == "gz", !name.lowercased().hasSuffix(".tar.gz") {
            // A single compressed file rather than a tarball.
            let output = ConversionCatalog.freeURL(in: url.deletingLastPathComponent(), base: base, ext: "")
            try shell("/usr/bin/gunzip", ["-k", "-c", url.path], stdout: output)
            return output
        } else {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try shell("/usr/bin/tar", ["-xf", url.path, "-C", folder.path])
        }
        return folder
    }

    private static func shell(_ tool: String, _ arguments: [String], in directory: URL? = nil, stdout: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let errors = Pipe()
        process.standardError = errors
        if let stdout {
            FileManager.default.createFile(atPath: stdout.path, contents: nil)
            process.standardOutput = try FileHandle(forWritingTo: stdout)
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed(message?.isEmpty == false ? message! : "\(URL(fileURLWithPath: tool).lastPathComponent) failed")
        }
    }
}

/// CSV / TSV reading and writing with RFC 4180 quoting.
enum DelimitedText {
    static func parse(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if char == "\"" {
                    // A doubled quote inside a quoted field is a literal quote.
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else { field.append(char) }
            } else if char == "\"", field.isEmpty {
                quoted = true
            } else if char == separator {
                row.append(field); field = ""
            } else if char == "\n" || char == "\r\n" || char == "\r" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func format(_ rows: [[String]], separator: Character) -> String {
        rows.map { row in
            row.map { field in
                let needsQuotes = field.contains(separator) || field.contains("\"") || field.contains("\n") || field.contains("\r")
                return needsQuotes ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: String(separator))
        }.joined(separator: "\n") + "\n"
    }

    static func html(_ rows: [[String]], title: String) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var lines = ["<!doctype html><meta charset=\"utf-8\"><title>\(escape(title))</title>",
                     "<style>table{border-collapse:collapse;font:13px -apple-system,sans-serif}td,th{border:1px solid #ccc;padding:4px 8px}th{background:#f3f3f3}</style>",
                     "<table>"]
        for (index, row) in rows.enumerated() {
            let tag = index == 0 ? "th" : "td"
            lines.append("<tr>" + row.map { "<\(tag)>\(escape($0))</\(tag)>" }.joined() + "</tr>")
        }
        lines.append("</table>")
        return lines.joined(separator: "\n") + "\n"
    }
}
