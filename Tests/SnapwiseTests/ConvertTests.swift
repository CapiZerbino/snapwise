import AVFoundation
import PDFKit
import XCTest
@testable import Snapwise

final class ConvertTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ contents: String = "") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func image(_ name: String, width: Int = 40, height: Int = 20) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try ImageConversions.write(TestImages.solid(width: width, height: height, (200, 30, 30)), to: url, ext: url.pathExtension)
        return url
    }

    // MARK: - Catalog

    func testFamiliesAndWheels() throws {
        let png = try image("a.png")
        XCTAssertEqual(FileFamily.of(png), .image)
        XCTAssertEqual(FileFamily.of(folder), .folder)
        XCTAssertEqual(FileFamily.of(URL(fileURLWithPath: "/x/notes.md")), .document)
        XCTAssertEqual(FileFamily.of(URL(fileURLWithPath: "/x/data.csv")), .table)
        XCTAssertEqual(FileFamily.of(URL(fileURLWithPath: "/x/a.tar.gz")), .archive)
        XCTAssertEqual(FileFamily.of(URL(fileURLWithPath: "/x/clip.mov")), .video)
        XCTAssertEqual(FileFamily.of(URL(fileURLWithPath: "/x/song.mp3")), .audio)
        XCTAssertEqual(FileFamily.of(URL(fileURLWithPath: "/x/book.pdf")), .pdf)

        let convert = ConversionCatalog.operations(for: [png], kind: .convert)
        XCTAssertFalse(convert.contains(.convert("png")), "no conversion to its own format")
        XCTAssertTrue(convert.contains(.convert("jpg")))
        let jpeg = URL(fileURLWithPath: "/x/photo.jpeg")
        XCTAssertFalse(ConversionCatalog.operations(for: [jpeg], kind: .convert).contains(.convert("jpg")), ".jpeg counts as JPG")

        XCTAssertTrue(ConversionCatalog.operations(for: [png], kind: .tools).contains(.tool(.annotate)))
        XCTAssertTrue(ConversionCatalog.operations(for: [png, png], kind: .tools).contains(.tool(.combineIntoPDF)))
        XCTAssertTrue(ConversionCatalog.operations(for: [png], kind: .actions).contains(.action(.float)))
        XCTAssertFalse(ConversionCatalog.operations(for: [folder], kind: .actions).contains(.action(.float)), "only images float")
        XCTAssertEqual(ConversionCatalog.operations(for: [png, URL(fileURLWithPath: "/x/a.csv")], kind: .convert), [], "mixed selection")
        XCTAssertTrue(ConversionCatalog.operations(for: [folder], kind: .tools).contains(.tool(.zip)))
        // Every wheel fits on one ring.
        for family in [png, jpeg, URL(fileURLWithPath: "/x/a.pdf"), URL(fileURLWithPath: "/x/a.mov")] {
            for kind in WheelKind.allCases { XCTAssertLessThanOrEqual(ConversionCatalog.operations(for: [family, family], kind: kind).count, 12) }
        }
    }

    func testTriggers() {
        XCTAssertEqual(WheelTrigger.only(in: [.shift]), .shift)
        XCTAssertNil(WheelTrigger.only(in: [.shift, .command]))
        XCTAssertNil(WheelTrigger.only(in: []))
        XCTAssertEqual(WheelTrigger.only(in: [.command, .capsLock]), .command)
    }

    func testFreeURLNeverOverwrites() throws {
        let first = ConversionCatalog.output(for: folder.appendingPathComponent("shot.png"), ext: "jpg")
        XCTAssertEqual(first.lastPathComponent, "shot.jpg")
        try "x".write(to: first, atomically: true, encoding: .utf8)
        XCTAssertEqual(ConversionCatalog.output(for: folder.appendingPathComponent("shot.png"), ext: "jpg").lastPathComponent, "shot 2.jpg")
        XCTAssertEqual(ConversionCatalog.output(for: folder.appendingPathComponent("a.png"), ext: "png", suffix: "50%").lastPathComponent, "a (50%).png")
    }

    // MARK: - Tables

    func testDelimitedTextRoundTrip() {
        let csv = "name,note\n\"Smith, J\",\"says \"\"hi\"\"\"\nplain,\"two\nlines\"\n"
        let rows = DelimitedText.parse(csv, separator: ",")
        XCTAssertEqual(rows, [["name", "note"], ["Smith, J", "says \"hi\""], ["plain", "two\nlines"]])
        XCTAssertEqual(DelimitedText.parse(DelimitedText.format(rows, separator: "\t"), separator: "\t"), rows)
        XCTAssertEqual(DelimitedText.format(rows, separator: ","), csv)
        XCTAssertEqual(DelimitedText.parse("a,b\r\nc,d", separator: ","), [["a", "b"], ["c", "d"]])
        XCTAssertTrue(DelimitedText.html([["<b>"]], title: "t").contains("&lt;b&gt;"))
    }

    // MARK: - Real conversions

    func testImageConversionsAndTools() throws {
        let png = try image("pic.png", width: 40, height: 20)
        for ext in ["jpg", "heic", "avif", "tiff", "gif", "bmp", "ico", "icns", "pdf"] {
            let output = try ImageConversions.convert(png, to: ext)
            XCTAssertEqual(output.pathExtension, ext)
            XCTAssertGreaterThan(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0, ext)
        }
        let rotated = try ImageConversions.run(.rotate, on: [png])[0]
        let loaded = try ImageConversions.load(rotated)
        XCTAssertEqual([loaded.width, loaded.height], [20, 40])
        let half = try ImageConversions.load(try ImageConversions.run(.resizeHalf, on: [png])[0])
        XCTAssertEqual([half.width, half.height], [20, 10])
        let combined = try ImageConversions.run(.combineIntoPDF, on: [png, png])[0]
        XCTAssertEqual(PDFDocument(url: combined)?.pageCount, 2)
        // JPEG has no alpha: a transparent pixel must come out white, not black.
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let clear = context.makeImage()!
        XCTAssertTrue(ImageConversions.hasAlpha(clear))
        XCTAssertEqual(TestImages.color(in: ImageConversions.flattened(clear), x: 1, y: 1).0, 255)
    }

    func testPDFPagesAndTools() throws {
        let png = try image("page.png", width: 72, height: 72)
        let pdf = try ImageConversions.convert(png, to: "pdf")
        let pageImage = try DocumentConversions.convert(pdf: pdf, to: "png")
        let rendered = try ImageConversions.load(pageImage)
        XCTAssertEqual(rendered.width, 300, "72 pt at 300 DPI")
        let merged = try DocumentConversions.run(.mergePDFs, on: [pdf, pdf])[0]
        XCTAssertEqual(PDFDocument(url: merged)?.pageCount, 2)
        let pages = try DocumentConversions.run(.splitPDF, on: [merged])[0]
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pages.path).count, 2)
        let rotated = try DocumentConversions.run(.rotatePDF, on: [pdf])[0]
        XCTAssertEqual(PDFDocument(url: rotated)?.page(at: 0)?.rotation, 90)
    }

    func testDocumentConversions() throws {
        let markdown = try file("notes.md", "# Title\n\nSome **bold** text.")
        let docx = try DocumentConversions.convert(document: markdown, to: "docx")
        let back = try NSAttributedString(url: docx, options: [:], documentAttributes: nil)
        XCTAssertTrue(back.string.contains("bold"))
        let html = try DocumentConversions.convert(document: docx, to: "html")
        XCTAssertTrue(try String(contentsOf: html, encoding: .utf8).contains("bold"))
        let txt = try DocumentConversions.convert(document: docx, to: "txt")
        XCTAssertTrue(try String(contentsOf: txt, encoding: .utf8).contains("Some"))
        let csv = try file("t.csv", "a,b\n1,2\n")
        let tsv = try DocumentConversions.convert(table: csv, to: "tsv")
        XCTAssertEqual(try String(contentsOf: tsv, encoding: .utf8), "a\tb\n1\t2\n")
    }

    func testArchiveRoundTrip() throws {
        let a = try file("a.txt", "alpha"), b = try file("b.txt", "beta")
        let zip = try DocumentConversions.archive([a, b], tarGz: false)
        XCTAssertEqual(zip.lastPathComponent, "Archive.zip")
        let extracted = try DocumentConversions.extract(zip)
        XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("b.txt"), encoding: .utf8), "beta")
        let tar = try DocumentConversions.archive([a], tarGz: true)
        XCTAssertEqual(tar.lastPathComponent, "a.txt.tar.gz")
        let untarred = try DocumentConversions.extract(tar)
        XCTAssertEqual(try String(contentsOf: untarred.appendingPathComponent("a.txt"), encoding: .utf8), "alpha")
    }

    func testAudioConversions() async throws {
        // A short sine tone as the source.
        let wav = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        do {
            let file = try AVAudioFile(forWriting: wav, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                                                                    AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050)!
            buffer.frameLength = 22_050
            for i in 0..<22_050 { buffer.floatChannelData![0][i] = sin(Float(i) * 0.06) * 0.4 }
            try file.write(from: buffer)
        }
        for ext in ["flac", "aiff", "caf", "m4a"] {
            let output = try await MediaConversions.convert(wav, to: ext)
            let converted = try AVAudioFile(forReading: output)
            XCTAssertEqual(Double(converted.length) / converted.fileFormat.sampleRate, 0.5, accuracy: 0.05, ext)
        }
    }
}
