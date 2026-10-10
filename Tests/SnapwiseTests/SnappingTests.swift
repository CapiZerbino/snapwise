import XCTest
@testable import Snapwise

final class SnappingTests: XCTestCase {
    /// Usable area of a 1440×900 display below a 25 pt menu bar, top-left origin.
    private let area = CGRect(x: 0, y: 25, width: 1440, height: 875)

    func testHalvesAndQuartersTileTheAreaExactly() {
        XCTAssertEqual(SnapPosition.leftHalf.frame(in: area, gap: 0), CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(SnapPosition.rightHalf.frame(in: area, gap: 0), CGRect(x: 720, y: 25, width: 720, height: 875))
        XCTAssertEqual(SnapPosition.maximize.frame(in: area, gap: 0), area)
        let quarters: [SnapPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let frames = quarters.compactMap { $0.frame(in: area, gap: 0) }
        XCTAssertEqual(frames.reduce(CGRect.null) { $0.union($1) }.integral, area.integral)
        XCTAssertEqual(frames[0].maxX, frames[1].minX, "quarters meet without overlapping")
        XCTAssertEqual(SnapPosition.bottomRight.frame(in: area, gap: 0)?.origin.x, 720)
    }

    func testThirdsCoverTheWidth() {
        let thirds: [SnapPosition] = [.leftThird, .centerThird, .rightThird]
        let frames = thirds.compactMap { $0.frame(in: area, gap: 0) }
        XCTAssertEqual(frames.map(\.width), [480, 480, 480])
        XCTAssertEqual(frames.map(\.minX), [0, 480, 960])
        XCTAssertEqual(SnapPosition.leftTwoThirds.frame(in: area, gap: 0)?.width, 960)
        XCTAssertEqual(SnapPosition.rightTwoThirds.frame(in: area, gap: 0)?.minX, 480)
    }

    func testGapIsUniformBetweenWindowsAndAtTheEdges() {
        let left = SnapPosition.leftHalf.frame(in: area, gap: 20)!
        let right = SnapPosition.rightHalf.frame(in: area, gap: 20)!
        XCTAssertEqual(left.minX - area.minX, 20)
        XCTAssertEqual(right.minX - left.maxX, 20)
        XCTAssertEqual(area.maxX - right.maxX, 20)
        XCTAssertEqual(left.minY - area.minY, 20)
    }

    func testWindowDependentPositionsHaveNoFixedFrame() {
        for position in [SnapPosition.center, .nextDisplay, .previousDisplay, .restore] {
            XCTAssertNil(position.frame(in: area, gap: 0), position.rawValue)
        }
    }

    func testFractionsRoundTripAndTransferBetweenDisplays() {
        let frame = CGRect(x: 360, y: 25, width: 720, height: 437.5)
        let f = SnapGeometry.fractions(of: frame, in: area)
        XCTAssertEqual(f, CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(SnapGeometry.frame(fractions: f, in: area, gap: 0), frame.roundedEdges)

        let other = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(SnapGeometry.transfer(frame, from: area, to: other), CGRect(x: 2080, y: 0, width: 1280, height: 720))
        XCTAssertEqual(SnapGeometry.fractions(of: frame, in: .zero), .zero, "degenerate area")
        // A window hanging off the source display is clamped into the target.
        let overflow = SnapGeometry.transfer(CGRect(x: 1000, y: 25, width: 2000, height: 875), from: area, to: other)
        XCTAssertLessThanOrEqual(overflow.width, other.width)
    }

    func testDragZones() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900) // AppKit coordinates: y grows upward
        func zone(_ x: CGFloat, _ y: CGFloat) -> SnapPosition? { SnapGeometry.position(forPointer: CGPoint(x: x, y: y), in: screen) }
        XCTAssertEqual(zone(0, 450), .leftHalf)
        XCTAssertEqual(zone(1439, 450), .rightHalf)
        XCTAssertEqual(zone(720, 899), .maximize)
        XCTAssertEqual(zone(2, 890), .topLeft)
        XCTAssertEqual(zone(1438, 890), .topRight)
        XCTAssertEqual(zone(2, 10), .bottomLeft)
        XCTAssertEqual(zone(1438, 10), .bottomRight)
        XCTAssertEqual(zone(40, 899), .topLeft, "end of the top edge is a corner")
        XCTAssertNil(zone(720, 1), "the middle of the bottom edge is left free for the Dock")
        XCTAssertNil(zone(720, 450))
        XCTAssertNil(zone(-200, 450), "pointer on another display")
    }

    func testEverySnapPositionHasAnActionAndUniqueShortcut() {
        XCTAssertEqual(Set(AppAction.snapActions.compactMap(\.snapPosition)), Set(SnapPosition.allCases))
        XCTAssertNil(AppAction.captureArea.snapPosition)
        XCTAssertEqual(AppAction.snapLeftHalf.title, "Left Half")
    }

    func testCustomAreaCoding() throws {
        let areaDefinition = CustomSnapArea(name: "Chat", x: 0.7, y: 0, width: 0.3, height: 1)
        let decoded = try JSONDecoder().decode([CustomSnapArea].self, from: JSONEncoder().encode([areaDefinition]))
        XCTAssertEqual(decoded, [areaDefinition])
        XCTAssertEqual(SnapGeometry.frame(fractions: areaDefinition.fractions, in: area, gap: 0), CGRect(x: 1008, y: 25, width: 432, height: 875))
    }

    func testTitlebarButtonPreferenceKeys() {
        XCTAssertEqual(TitlebarButtonTap.prefKey(subrole: kAXZoomButtonSubrole, middle: false), "titlebarZoomRight")
        XCTAssertEqual(TitlebarButtonTap.prefKey(subrole: kAXFullScreenButtonSubrole, middle: true), "titlebarZoomMiddle")
        XCTAssertEqual(TitlebarButtonTap.prefKey(subrole: kAXCloseButtonSubrole, middle: false), "titlebarCloseRight")
        XCTAssertNil(TitlebarButtonTap.prefKey(subrole: "AXToolbarButton", middle: false))
    }

    func testRectCloseness() {
        let r = CGRect(x: 10, y: 10, width: 100, height: 100)
        XCTAssertTrue(r.isClose(to: r.offsetBy(dx: 2, dy: -2)))
        XCTAssertFalse(r.isClose(to: r.offsetBy(dx: 8, dy: 0)))
    }

    func testRepeatedHalfShortcutCyclesThroughSizes() {
        var frame = CGRect(x: 300, y: 200, width: 500, height: 400)
        var widths: [CGFloat] = []
        for _ in 0..<4 {
            frame = SnapGeometry.nextFrame(for: .leftHalf, current: frame, in: area, gap: 0)!
            widths.append(frame.width)
            XCTAssertEqual(frame.minX, 0, "stays anchored to the left edge")
        }
        XCTAssertEqual(widths, [720, 960, 480, 720])

        let right = SnapGeometry.nextFrame(for: .rightHalf, current: SnapPosition.rightHalf.frame(in: area, gap: 0)!, in: area, gap: 0)!
        XCTAssertEqual(right, CGRect(x: 480, y: 25, width: 960, height: 875), "right side grows leftward")
        let bottom = SnapGeometry.nextFrame(for: .bottomHalf, current: SnapPosition.bottomHalf.frame(in: area, gap: 0)!, in: area, gap: 0)!
        XCTAssertEqual(bottom.maxY, area.maxY)
        XCTAssertEqual(bottom.height, 583, accuracy: 1)
    }

    func testCyclingCanBeDisabledAndIgnoresOtherPositions() {
        let half = SnapPosition.leftHalf.frame(in: area, gap: 0)!
        XCTAssertEqual(SnapGeometry.nextFrame(for: .leftHalf, current: half, in: area, gap: 0, cycling: false), half)
        let quarter = SnapPosition.topLeft.frame(in: area, gap: 0)!
        XCTAssertEqual(SnapGeometry.nextFrame(for: .topLeft, current: quarter, in: area, gap: 0), quarter)
        XCTAssertNil(SnapGeometry.nextFrame(for: .center, current: half, in: area, gap: 0))
    }

    func testCyclingRespectsGaps() {
        let first = SnapGeometry.nextFrame(for: .leftHalf, current: .zero, in: area, gap: 16)!
        let second = SnapGeometry.nextFrame(for: .leftHalf, current: first, in: area, gap: 16)!
        XCTAssertEqual(first.minX, 16)
        XCTAssertGreaterThan(second.width, first.width)
        XCTAssertEqual(second.minX, 16)
    }
}
