import Carbon.HIToolbox
import XCTest
@testable import Snapwise

final class CoreLogicTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("snapwise-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - File names

    func testFilenameTemplateExpandsTokens() {
        let date = Date(timeIntervalSince1970: 1_780_000_000) // 2026-05-28 20:26:40 UTC
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(FilenameTemplate.render("Shot {date} at {time} ({kind})", date: date, kind: "GIF", timeZone: utc),
                       "Shot 2026-05-28 at 20.26.40 (GIF)")
        XCTAssertEqual(FilenameTemplate.render("", date: date, kind: "x", timeZone: utc), "Snapwise 2026-05-28 at 20.26.40")
        XCTAssertEqual(FilenameTemplate.render("a/b:c", date: date, kind: "x", timeZone: utc), "a-b.c", "path separators are neutralized")
    }

    func testUniqueURLAvoidsCollisions() throws {
        let first = FilenameTemplate.uniqueURL(folder: tempDir, name: "Shot", ext: "png")
        XCTAssertEqual(first.lastPathComponent, "Shot.png")
        try Data().write(to: first)
        let second = FilenameTemplate.uniqueURL(folder: tempDir, name: "Shot", ext: "png")
        XCTAssertEqual(second.lastPathComponent, "Shot 2.png")
        try Data().write(to: second)
        XCTAssertEqual(FilenameTemplate.uniqueURL(folder: tempDir, name: "Shot", ext: "png").lastPathComponent, "Shot 3.png")
    }

    func testImageEncodingKeepsPixelsAndFormats() {
        let image = TestImages.noise(width: 40, height: 30, seed: 3)
        for format in ImageFormat.allCases {
            let data = image.encoded(as: format, scale: 2)
            XCTAssertNotNil(data, format.rawValue)
            let decoded = data.flatMap { NSImage(data: $0)?.cgImage }
            XCTAssertEqual(decoded?.width, 40, "\(format): Retina DPI metadata must not shrink the pixels")
            XCTAssertEqual(decoded?.height, 30)
        }
        let png = image.encoded(as: .png).flatMap { NSImage(data: $0)?.cgImage }
        XCTAssertEqual(png.map { TestImages.maxDifference($0, image) }, 0)
    }

    // MARK: - Hotkeys and colors

    func testHotkeyStorageAndDisplay() {
        let hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(Hotkey(stored: hotkey.stored), hotkey)
        XCTAssertEqual(hotkey.display, "⇧⌘4")
        XCTAssertEqual(hotkey.cocoaModifiers, [.command, .shift])
        XCTAssertNil(Hotkey(stored: ""), "an empty value means the shortcut was cleared")
        XCTAssertNil(Hotkey(stored: "garbage"))
        XCTAssertEqual(Hotkey.carbon(from: [.control, .option]), UInt32(controlKey | optionKey))
    }

    func testDefaultHotkeysAreUnique() {
        let defaults = AppAction.allCases.compactMap { $0.defaultHotkey?.stored }
        XCTAssertEqual(Set(defaults).count, defaults.count)
        XCTAssertEqual(Set(AppAction.allCases.map(\.rawValue)).count, AppAction.allCases.count)
    }

    func testHexColors() {
        XCTAssertEqual(NSColor(hex: "#FF8000").hexString, "#FF8000FF")
        XCTAssertEqual(NSColor(hex: "00FF0080").hexString, "#00FF0080")
        XCTAssertEqual(RGBA(hex: "#000000"), RGBA(r: 0, g: 0, b: 0, a: 1))
    }

    // MARK: - Geometry

    func testGeometryHelpers() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(Geo.flipGlobal(Geo.flipGlobal(rect)), rect)
        XCTAssertEqual(CGRect(from: CGPoint(x: 50, y: 5), to: CGPoint(x: 10, y: 25)), CGRect(x: 10, y: 5, width: 40, height: 20))
        XCTAssertEqual(Geo.aspectFit(CGSize(width: 400, height: 200), in: CGSize(width: 100, height: 100)), CGSize(width: 100, height: 50))
        XCTAssertEqual(Geo.aspectFit(.zero, in: CGSize(width: 100, height: 100)), .zero)
        XCTAssertEqual(CGPoint(x: 5, y: 5).distance(toSegment: .zero, CGPoint(x: 10, y: 0)), 5)
        XCTAssertEqual(CGPoint(x: 13, y: 4).distance(toSegment: .zero, CGPoint(x: 10, y: 0)), 5, "beyond the end uses the endpoint")
        XCTAssertEqual(CGPoint(x: 3, y: 4).distance(toSegment: .zero, .zero), 5, "degenerate segment")
    }

    // MARK: - History

    func testHistoryStorePersistsAndPurges() {
        let image = TestImages.noise(width: 32, height: 24, seed: 1)
        let store = HistoryStore(directory: tempDir)
        let item = store.add(image: image, scale: 2)
        XCTAssertNotNil(item)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].width, 32)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(store.items[0].fileName).path))

        XCTAssertEqual(HistoryStore(directory: tempDir).items, store.items, "index is reloaded from disk")

        store.purgeExpired(now: Date().addingTimeInterval(86_400 * 3), retentionDays: 7)
        XCTAssertEqual(store.items.count, 1, "newer than the retention window")
        store.purgeExpired(now: Date().addingTimeInterval(86_400 * 8), retentionDays: 0)
        XCTAssertEqual(store.items.count, 1, "0 keeps captures forever")
        store.purgeExpired(now: Date().addingTimeInterval(86_400 * 8), retentionDays: 7)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(HistoryStore(directory: tempDir).items.isEmpty)
    }

    func testHistoryDropsEntriesWhoseFileIsGone() throws {
        let store = HistoryStore(directory: tempDir)
        let item = try XCTUnwrap(store.add(image: TestImages.solid(width: 8, height: 8, (1, 2, 3)), scale: 1))
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent(item.fileName))
        XCTAssertTrue(HistoryStore(directory: tempDir).items.isEmpty)
    }

    func testHistoryAdoptsRecordingFiles() throws {
        let source = tempDir.appendingPathComponent("clip.mp4")
        try Data([1, 2, 3]).write(to: source)
        let folder = tempDir.appendingPathComponent("store", isDirectory: true)
        let store = HistoryStore(directory: folder)
        let item = try XCTUnwrap(store.add(fileAt: source, kind: .video, pixelSize: CGSize(width: 640, height: 480), scale: 2))
        XCTAssertEqual(item.kind, .video)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "the temp file is moved, not copied")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(item.fileName).path))
        XCTAssertNil(store.add(fileAt: source, kind: .video, pixelSize: .zero, scale: 1), "a missing source fails cleanly")
        store.delete(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(item.fileName).path))
    }

    // MARK: - Recording math

    func testEncodableSizeIsEvenAndCapped() {
        XCTAssertEqual(RecordingManager.encodableSize(CGSize(width: 801, height: 601)), CGSize(width: 800, height: 600))
        let big = RecordingManager.encodableSize(CGSize(width: 5120, height: 2880))
        XCTAssertEqual(big, CGSize(width: 3840, height: 2160))
        XCTAssertEqual(RecordingManager.encodableSize(CGSize(width: 1, height: 1)), CGSize(width: 2, height: 2))
    }

    func testClickZoomRampsInHoldsAndReleases() {
        let clicks = [ClickEvent(t: 5, x: 0.2, y: 0.8)]
        func zoom(_ t: Double) -> Double { ClickZoom.state(at: t, clicks: clicks, maxScale: 2).scale }
        XCTAssertEqual(zoom(0), 1)
        XCTAssertEqual(zoom(4.5), 1, accuracy: 0.05)
        XCTAssertGreaterThan(zoom(4.8), 1)
        XCTAssertLessThan(zoom(4.8), 2)
        XCTAssertEqual(zoom(5), 2, accuracy: 0.001)
        XCTAssertEqual(zoom(6.5), 2, accuracy: 0.001)
        XCTAssertLessThan(zoom(6.9), 2)
        XCTAssertEqual(zoom(8), 1)
        let focus = ClickZoom.state(at: 5.5, clicks: clicks, maxScale: 2)
        XCTAssertEqual(focus.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(focus.y, 0.8, accuracy: 0.001)
        XCTAssertEqual(ClickZoom.state(at: 5, clicks: [], maxScale: 2).scale, 1)
    }

    func testClickZoomPansBetweenOverlappingClicks() {
        let clicks = [ClickEvent(t: 1, x: 0, y: 0), ClickEvent(t: 2, x: 1, y: 1)]
        let mid = ClickZoom.state(at: 2, clicks: clicks, maxScale: 2)
        XCTAssertEqual(mid.scale, 2, accuracy: 0.001)
        XCTAssertEqual(mid.x, 0.5, accuracy: 0.001, "both clicks are fully active, so the focus sits between them")
    }

    func testVideoLayout() {
        let natural = CGSize(width: 1920, height: 1080)
        var options = VideoExportOptions()
        XCTAssertEqual(VideoExporter.layout(natural: natural, options: options),
                       VideoExporter.Layout(canvas: natural, content: CGRect(origin: .zero, size: natural)))

        options.format = "1:1"
        let square = VideoExporter.layout(natural: natural, options: options)
        XCTAssertEqual(square.canvas, CGSize(width: 1920, height: 1920))
        XCTAssertEqual(square.content, CGRect(x: 0, y: 420, width: 1920, height: 1080))

        options.format = "9:16"
        let vertical = VideoExporter.layout(natural: natural, options: options).canvas
        XCTAssertEqual(vertical.width / vertical.height, 9.0 / 16, accuracy: 0.01)

        options.format = "original"
        options.backgroundIndex = 2
        options.padding = 0.1
        let padded = VideoExporter.layout(natural: natural, options: options)
        XCTAssertEqual(padded.canvas, natural)
        XCTAssertEqual(padded.content.height, 864, accuracy: 0.5)
        XCTAssertEqual(padded.content.midX, 960, accuracy: 0.5)

        options.maxHeight = 720
        XCTAssertEqual(VideoExporter.layout(natural: natural, options: options).canvas, CGSize(width: 1280, height: 720))
    }

    func testKeystrokeDescriptions() throws {
        func event(_ key: String, code: UInt16, flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                           characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
        }
        XCTAssertEqual(KeystrokeOverlay.describe(try event("s", code: 1, flags: [.command, .shift]), commandsOnly: true)?.text, "⇧⌘S")
        XCTAssertNil(KeystrokeOverlay.describe(try event("a", code: 0, flags: []), commandsOnly: true))
        XCTAssertEqual(KeystrokeOverlay.describe(try event("a", code: 0, flags: []), commandsOnly: false)?.text, "A")
        XCTAssertEqual(KeystrokeOverlay.describe(try event("\r", code: 36, flags: []), commandsOnly: false)?.text, "↩")
    }

    func testWindowBackgroundComposerAddsPaddingOnlyWhenNeeded() {
        let window = TestImages.solid(width: 100, height: 80, (10, 20, 30))
        let prefs = Prefs.shared
        let saved = (prefs.windowBackground, prefs.windowShadow, prefs.windowPadding)
        defer { (prefs.windowBackground, prefs.windowShadow, prefs.windowPadding) = saved }

        prefs.windowBackground = "transparent"
        prefs.windowShadow = false
        XCTAssertEqual(WindowBackgroundComposer.compose(window: window, scale: 2, screen: nil).size, CGSize(width: 100, height: 80))

        prefs.windowBackground = "solid"
        prefs.windowPadding = 30
        let composed = WindowBackgroundComposer.compose(window: window, scale: 2, screen: nil)
        XCTAssertEqual(composed.size, CGSize(width: 220, height: 200))
        XCTAssertEqual(TestImages.color(in: composed, x: 110, y: 100).2, 30, "window pixels are preserved in the middle")
    }
}
