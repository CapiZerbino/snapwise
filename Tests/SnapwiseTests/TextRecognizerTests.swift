import XCTest
@testable import Snapwise

final class TextRecognizerTests: XCTestCase {
    /// White canvas with black text, like a typical screenshot of a document.
    private func render(_ lines: [String], size: CGSize = CGSize(width: 900, height: 300)) -> CGImage {
        let ctx = CGContext.bitmap(width: Int(size.width), height: Int(size.height))!
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (index, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
                .draw(at: CGPoint(x: 30, y: size.height - 80 - CGFloat(index) * 70))
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    func testRecognizesPrintedText() {
        let text = TextRecognizer.recognize(render(["Hello Snapwise 12345", "Second line of text"]))
        XCTAssertTrue(text.contains("Hello Snapwise 12345"), "got: \(text)")
        XCTAssertTrue(text.contains("Second line of text"), "got: \(text)")
        XCTAssertEqual(text.components(separatedBy: "\n").count, 2)
    }

    func testRecognizesVietnameseDiacritics() {
        let text = TextRecognizer.recognize(render(["Xin chào, đây là tiếng Việt"]))
        // Vision occasionally drops one tone mark; require the words that carry distinct diacritics.
        XCTAssertTrue(text.contains("chào") && text.contains("Việt") && text.contains("đây"), "got: \(text)")
    }

    func testBlankImageYieldsNoText() {
        XCTAssertEqual(TextRecognizer.recognize(TestImages.solid(width: 200, height: 100, (255, 255, 255))), "")
    }
}
