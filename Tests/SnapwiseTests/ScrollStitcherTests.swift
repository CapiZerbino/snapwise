import XCTest
@testable import Snapwise

final class ScrollStitcherTests: XCTestCase {
    private let width = 240, frameHeight = 300

    func testVerticalFramesRebuildTheFullPage() {
        let page = TestImages.noise(width: width, height: 1200, seed: 7)
        var stitcher = ScrollStitcher()
        for offset in [0, 70, 150, 150, 262, 400, 533, 700, 811, 900] {
            stitcher.add(TestImages.crop(page, x: 0, y: offset, width: width, height: frameHeight))
        }
        let result = stitcher.result()
        XCTAssertEqual(stitcher.axis, .vertical)
        XCTAssertEqual(result?.height, 1200)
        XCTAssertEqual(result?.width, width)
        XCTAssertEqual(result.map { TestImages.maxDifference($0, page) }, 0)
    }

    func testHorizontalScrollingIsDetected() {
        let page = TestImages.transpose(TestImages.noise(width: width, height: 1000, seed: 11))
        var stitcher = ScrollStitcher()
        for offset in [0, 60, 180, 333, 500, 700] {
            stitcher.add(TestImages.crop(page, x: offset, y: 0, width: frameHeight, height: width))
        }
        let result = stitcher.result()
        XCTAssertEqual(stitcher.axis, .horizontal)
        XCTAssertEqual(result?.width, 1000)
        XCTAssertEqual(result.map { TestImages.maxDifference($0, page) }, 0)
    }

    func testStickyHeaderAndFooterAppearOnce() {
        let header = TestImages.noise(width: width, height: 40, seed: 1)
        let footer = TestImages.noise(width: width, height: 30, seed: 2)
        let content = TestImages.noise(width: width, height: 900, seed: 3)
        let visible = frameHeight - 70
        var stitcher = ScrollStitcher()
        for offset in [0, 90, 200, 310, 450, 560, 670] {
            let window = TestImages.crop(content, x: 0, y: offset, width: width, height: visible)
            stitcher.add(TestImages.stack([header, window, footer]))
        }
        let expected = TestImages.stack([header, TestImages.crop(content, x: 0, y: 0, width: width, height: 670 + visible), footer])
        let result = stitcher.result()
        XCTAssertEqual(result?.height, expected.height)
        XCTAssertEqual(result.map { TestImages.maxDifference($0, expected) }, 0)
    }

    func testIdenticalFramesDoNotGrow() {
        let frame = TestImages.noise(width: width, height: frameHeight, seed: 5)
        var stitcher = ScrollStitcher()
        XCTAssertTrue(stitcher.add(frame))
        XCTAssertFalse(stitcher.add(frame))
        XCTAssertFalse(stitcher.add(frame))
        XCTAssertEqual(stitcher.addedLines, 0)
        XCTAssertEqual(stitcher.result()?.height, frameHeight)
    }

    func testUniformContentIsNotStitched() {
        // A blank page aligns at every offset, so no scroll distance can be trusted.
        var stitcher = ScrollStitcher()
        stitcher.add(TestImages.solid(width: width, height: frameHeight, (255, 255, 255)))
        XCTAssertFalse(stitcher.add(TestImages.solid(width: width, height: frameHeight, (250, 250, 250))))
        XCTAssertEqual(stitcher.result()?.height, frameHeight)
    }

    func testFramesOfDifferentSizeAreRejected() {
        var stitcher = ScrollStitcher()
        stitcher.add(TestImages.noise(width: width, height: frameHeight, seed: 5))
        XCTAssertFalse(stitcher.add(TestImages.noise(width: width, height: frameHeight + 10, seed: 6)))
    }

    func testUnrelatedFrameIsIgnored() {
        var stitcher = ScrollStitcher()
        stitcher.add(TestImages.noise(width: width, height: frameHeight, seed: 5))
        XCTAssertFalse(stitcher.add(TestImages.noise(width: width, height: frameHeight, seed: 99)))
    }
}
