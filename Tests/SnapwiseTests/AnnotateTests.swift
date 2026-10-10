import XCTest
@testable import Snapwise

final class AnnotateTests: XCTestCase {
    private let white = TestImages.solid(width: 200, height: 120, (255, 255, 255))
    private let red = RGBA(r: 1, g: 0, b: 0)

    private func model(_ image: CGImage? = nil, scale: CGFloat = 1) -> EditorModel {
        EditorModel(image: image ?? white, scale: scale)
    }

    private func annotation(_ tool: Tool, _ start: CGPoint, _ end: CGPoint, width: CGFloat = 4) -> Annotation {
        Annotation(tool: tool, start: start, end: end, color: red, lineWidth: width)
    }

    func testFilledRectIsDrawnAtTopLeftBasedCoordinates() {
        let m = model()
        m.add(annotation(.filledRect, CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)))
        let out = m.exported()
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 120)
        let inside = TestImages.color(in: out, x: 30, y: 20)
        XCTAssertGreaterThan(inside.0, 240)
        XCTAssertLessThan(inside.1, 20)
        // The mirrored position would be red if the y axis were flipped.
        let mirrored = TestImages.color(in: out, x: 30, y: 100)
        XCTAssertEqual(mirrored.1, 255)
    }

    func testEveryToolRendersWithoutChangingCanvasSize() {
        let m = model(TestImages.noise(width: 200, height: 120, seed: 4))
        for tool in Tool.toolbar where tool != .select && tool != .crop {
            var a = m.makeAnnotation(tool, at: CGPoint(x: 20, y: 20))
            a.end = CGPoint(x: 150, y: 90)
            a.points = [CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 70), CGPoint(x: 150, y: 90)]
            a.text = "Hello"
            m.add(a)
        }
        for style in ArrowStyle.allCases {
            var a = annotation(.arrow, CGPoint(x: 10, y: 100), CGPoint(x: 180, y: 15))
            a.arrowStyle = style
            m.add(a)
        }
        for style in TextStyle.allCases {
            var a = annotation(.text, CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5))
            a.text = "Style"
            a.textStyle = style
            m.add(a)
        }
        let out = m.exported()
        XCTAssertEqual(out.size, CGSize(width: 200, height: 120))
        XCTAssertGreaterThan(TestImages.maxDifference(out, m.state.base), 0)
    }

    func testBlurStylesObscureDetailOnlyInsideTheirRect() {
        let noise = TestImages.noise(width: 200, height: 120, seed: 9, block: 2)
        for style in BlurStyle.allCases {
            let m = model(noise)
            var a = annotation(.blur, CGPoint(x: 40, y: 20), CGPoint(x: 160, y: 100))
            a.blurStyle = style
            m.add(a)
            let out = m.exported()
            let inside = TestImages.crop(out, x: 60, y: 40, width: 60, height: 40)
            XCTAssertGreaterThan(TestImages.maxDifference(inside, TestImages.crop(noise, x: 60, y: 40, width: 60, height: 40)), 20, "\(style)")
            let outside = TestImages.crop(out, x: 0, y: 0, width: 30, height: 120)
            XCTAssertEqual(TestImages.maxDifference(outside, TestImages.crop(noise, x: 0, y: 0, width: 30, height: 120)), 0, "\(style)")
        }
    }

    func testSpotlightDimsEverythingOutside() {
        let m = model()
        m.add(annotation(.spotlight, CGPoint(x: 50, y: 30), CGPoint(x: 150, y: 90)))
        let out = m.exported()
        XCTAssertEqual(TestImages.color(in: out, x: 100, y: 60).0, 255)
        XCTAssertLessThan(TestImages.color(in: out, x: 10, y: 10).0, 140)
    }

    func testUndoRedoRestoreAnnotations() {
        let m = model()
        m.add(annotation(.rect, .zero, CGPoint(x: 20, y: 20)))
        m.add(annotation(.line, .zero, CGPoint(x: 50, y: 50)))
        XCTAssertEqual(m.state.annotations.count, 2)
        m.undo()
        XCTAssertEqual(m.state.annotations.count, 1)
        m.undo()
        XCTAssertEqual(m.state.annotations.count, 0)
        m.undo() // nothing left: must be a no-op
        m.redo()
        m.redo()
        XCTAssertEqual(m.state.annotations.map(\.tool), [.rect, .line])
        XCTAssertTrue(m.isDirty)
    }

    func testCropShiftsAnnotationsAndIsUndoable() {
        let m = model()
        m.add(annotation(.filledRect, CGPoint(x: 100, y: 60), CGPoint(x: 140, y: 100)))
        m.cropRect = CGRect(x: 80, y: 40, width: 100, height: 70)
        m.applyCrop()
        XCTAssertEqual(m.state.size, CGSize(width: 100, height: 70))
        XCTAssertEqual(m.state.annotations[0].start, CGPoint(x: 20, y: 20))
        XCTAssertNil(m.cropRect)
        XCTAssertLessThan(TestImages.color(in: m.exported(), x: 30, y: 30).1, 20)
        m.undo()
        XCTAssertEqual(m.state.size, CGSize(width: 200, height: 120))
        XCTAssertEqual(m.state.annotations[0].start, CGPoint(x: 100, y: 60))
    }

    func testCropOutsideImageIsClampedAndTinyCropIgnored() {
        let m = model()
        m.cropRect = CGRect(x: 150, y: 80, width: 500, height: 500)
        m.applyCrop()
        XCTAssertEqual(m.state.size, CGSize(width: 50, height: 40))
        m.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        m.applyCrop()
        XCTAssertEqual(m.state.size, CGSize(width: 50, height: 40))
    }

    func testRotateAndFlipMovePixelsCorrectly() {
        // Red marker in the top-left corner of an otherwise white image.
        let image = TestImages.make(width: 40, height: 20) { x, y in x < 10 && y < 10 ? (255, 0, 0) : (255, 255, 255) }
        func isRed(_ image: CGImage, _ x: Int, _ y: Int) -> Bool {
            let c = TestImages.color(in: image, x: x, y: y)
            return c.0 > 200 && c.1 < 60
        }

        let rotated = model(image)
        rotated.rotate(clockwise: true)
        XCTAssertEqual(rotated.state.size, CGSize(width: 20, height: 40))
        XCTAssertTrue(isRed(rotated.state.base, 15, 5), "clockwise moves top-left to top-right")

        let counter = model(image)
        counter.rotate(clockwise: false)
        XCTAssertTrue(isRed(counter.state.base, 5, 35), "counter-clockwise moves top-left to bottom-left")

        let flippedH = model(image)
        flippedH.flip(horizontal: true)
        XCTAssertTrue(isRed(flippedH.state.base, 35, 5))

        let flippedV = model(image)
        flippedV.flip(horizontal: false)
        XCTAssertTrue(isRed(flippedV.state.base, 5, 15))
    }

    func testResizeKeepsAspectAndFlattens() {
        let m = model()
        m.add(annotation(.filledRect, .zero, CGPoint(x: 100, y: 120)))
        m.resize(toWidth: 100)
        XCTAssertEqual(m.state.size, CGSize(width: 100, height: 60))
        XCTAssertTrue(m.state.annotations.isEmpty)
        XCTAssertLessThan(TestImages.color(in: m.state.base, x: 20, y: 30).1, 30)
    }

    func testCounterNumbersIncrement() {
        let m = model()
        m.add(m.makeAnnotation(.counter, at: .zero))
        m.add(m.makeAnnotation(.counter, at: .zero))
        XCTAssertEqual(m.makeAnnotation(.counter, at: .zero).number, 3)
    }

    func testStyleControlsScaleWithRetinaFactor() {
        let m = model(scale: 2)
        m.lineWidth = 5
        m.fontSize = 20
        let a = m.makeAnnotation(.arrow, at: .zero)
        XCTAssertEqual(a.lineWidth, 10)
        XCTAssertEqual(a.fontSize, 40)
    }

    func testChangingColorUpdatesTheSelectedAnnotation() {
        let m = model()
        let a = annotation(.rect, .zero, CGPoint(x: 20, y: 20))
        m.add(a)
        m.tool = .select
        m.selectedID = a.id
        XCTAssertEqual(m.color, red, "selecting loads the annotation's style")
        m.color = RGBA(r: 0, g: 0, b: 1)
        XCTAssertEqual(m.state.annotations[0].color, RGBA(r: 0, g: 0, b: 1))
        m.undo()
        XCTAssertEqual(m.state.annotations[0].color, red)
    }

    func testHitTesting() {
        let line = annotation(.line, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), width: 2)
        XCTAssertTrue(line.hitTest(CGPoint(x: 50, y: 3), tolerance: 4))
        XCTAssertFalse(line.hitTest(CGPoint(x: 50, y: 20), tolerance: 4))
        XCTAssertFalse(line.hitTest(CGPoint(x: 130, y: 0), tolerance: 4))

        let outline = annotation(.rect, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100), width: 2)
        XCTAssertTrue(outline.hitTest(CGPoint(x: 1, y: 50), tolerance: 4), "stroke is hit")
        XCTAssertFalse(outline.hitTest(CGPoint(x: 50, y: 50), tolerance: 4), "hollow interior is not")

        let filled = annotation(.filledRect, CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 0))
        XCTAssertTrue(filled.hitTest(CGPoint(x: 50, y: 50), tolerance: 4), "reversed corners still normalize")
    }

    func testBackgroundLayout() {
        var bg = BackgroundSettings()
        let image = CGSize(width: 400, height: 200)
        XCTAssertEqual(bg.layout(imageSize: image, scale: 2).canvas, image, "disabled background adds nothing")

        bg.enabled = true
        bg.padding = 50
        let padded = bg.layout(imageSize: image, scale: 2)
        XCTAssertEqual(padded.canvas, CGSize(width: 600, height: 400))
        XCTAssertEqual(padded.content, CGRect(x: 100, y: 100, width: 400, height: 200))

        bg.aspect = "1:1"
        let square = bg.layout(imageSize: image, scale: 2)
        XCTAssertEqual(square.canvas, CGSize(width: 600, height: 600))
        XCTAssertEqual(square.content.origin, CGPoint(x: 100, y: 200))

        bg.alignment = 0
        XCTAssertEqual(bg.layout(imageSize: image, scale: 2).content.origin, .zero)
        bg.alignment = 8
        XCTAssertEqual(bg.layout(imageSize: image, scale: 2).content.origin, CGPoint(x: 200, y: 400))

        bg.aspect = "9:16"
        let tall = bg.layout(imageSize: image, scale: 2).canvas
        XCTAssertEqual(tall.width / tall.height, 9.0 / 16, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(tall.width, 600)
    }

    func testExportWithBackgroundUsesLayoutSizeAndKeepsImagePixels() {
        let m = model(TestImages.solid(width: 100, height: 60, (0, 0, 255)))
        m.background.enabled = true
        m.background.kind = "solid"
        m.background.solid = RGBA(r: 0, g: 1, b: 0)
        m.background.padding = 20
        m.background.cornerRadius = 0
        m.background.shadow = 0
        let out = m.exported()
        XCTAssertEqual(out.size, CGSize(width: 140, height: 100))
        XCTAssertEqual(TestImages.color(in: out, x: 5, y: 5).1, 255)
        XCTAssertEqual(TestImages.color(in: out, x: 70, y: 50).2, 255)
        XCTAssertTrue(m.isDirty)
    }

    func testAutoBalanceEqualizesMargins() {
        // Content block with margins left 10, right 50, top 20, bottom 4.
        let image = TestImages.make(width: 160, height: 100) { x, y in
            (10..<110).contains(x) && (20..<96).contains(y) ? (0, 0, 0) : (240, 240, 240)
        }
        XCTAssertEqual(AutoBalance.balancedCrop(of: image), CGRect(x: 0, y: 16, width: 120, height: 84))
        XCTAssertNil(AutoBalance.balancedCrop(of: TestImages.solid(width: 50, height: 50, (9, 9, 9))), "blank image")
        let centered = TestImages.make(width: 60, height: 60) { x, y in (10..<50).contains(x) && (10..<50).contains(y) ? (0, 0, 0) : (255, 255, 255) }
        XCTAssertNil(AutoBalance.balancedCrop(of: centered), "already balanced")
    }

    func testProjectFileRoundTrip() throws {
        let m = model(TestImages.noise(width: 64, height: 48, seed: 2), scale: 2)
        var text = m.makeAnnotation(.text, at: CGPoint(x: 5, y: 6))
        text.text = "Xin chào"
        text.textStyle = .darkBox
        m.add(text)
        m.add(annotation(.arrow, CGPoint(x: 1, y: 2), CGPoint(x: 30, y: 40)))
        m.background.enabled = true
        m.background.gradientIndex = 7

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ProjectFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectFile.write(m, to: url)
        let loaded = try ProjectFile.read(from: url)
        XCTAssertEqual(loaded.state.annotations, m.state.annotations)
        XCTAssertEqual(loaded.background, m.background)
        XCTAssertEqual(loaded.scale, 2)
        XCTAssertEqual(TestImages.maxDifference(loaded.state.base, m.state.base), 0)
        XCTAssertFalse(loaded.isDirty)
    }

    func testCorruptProjectFileThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".snapwise")
        try? Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ProjectFile.read(from: url))
    }

    func testStyleTweaksOnOneSelectionCollapseIntoOneUndoStep() {
        let m = model()
        let a = annotation(.rect, .zero, CGPoint(x: 20, y: 20))
        m.add(a)
        m.tool = .select
        m.selectedID = a.id
        for width in stride(from: 5.0, through: 12.0, by: 1.0) { m.lineWidth = width } // a slider drag
        XCTAssertEqual(m.undoStack.count, 2, "one entry for the add, one for the whole drag")
        m.undo()
        XCTAssertEqual(m.state.annotations[0].lineWidth, 4)
    }

    func testRestoreReplacesAnExistingAnnotationInsteadOfDuplicating() {
        let m = model()
        var a = annotation(.text, .zero, .zero)
        a.text = "one"
        m.add(a)
        a.text = "two"
        m.restore(a)
        XCTAssertEqual(m.state.annotations.map(\.text), ["two"])
    }
}
