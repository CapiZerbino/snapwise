import AppKit

/// A place a window can be snapped to. Raw values double as URL-scheme and hotkey identifiers (`snap-<raw>`).
enum SnapPosition: String, CaseIterable {
    case leftHalf = "left-half", rightHalf = "right-half", topHalf = "top-half", bottomHalf = "bottom-half"
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"
    case maximize, center
    case leftThird = "left-third", centerThird = "center-third", rightThird = "right-third"
    case leftTwoThirds = "left-two-thirds", rightTwoThirds = "right-two-thirds"
    case nextDisplay = "next-display", previousDisplay = "previous-display"
    case restore
    case moveLeft = "move-left", moveRight = "move-right", moveUp = "move-up", moveDown = "move-down"

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .nextDisplay: return "Move to Next Display"
        case .previousDisplay: return "Move to Previous Display"
        case .restore: return "Restore Original Size"
        case .moveLeft: return "Move to Left Edge"
        case .moveRight: return "Move to Right Edge"
        case .moveUp: return "Move to Top Edge"
        case .moveDown: return "Move to Bottom Edge"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .maximize: return "rectangle.inset.filled"
        case .center: return "rectangle.center.inset.filled"
        case .leftThird: return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .rightThird: return "rectangle.trailingthird.inset.filled"
        case .leftTwoThirds: return "rectangle.leadinghalf.inset.filled"
        case .rightTwoThirds: return "rectangle.trailinghalf.inset.filled"
        case .nextDisplay: return "arrow.right.to.line"
        case .previousDisplay: return "arrow.left.to.line"
        case .restore: return "arrow.uturn.backward"
        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        case .moveUp: return "arrow.up"
        case .moveDown: return "arrow.down"
        }
    }

    /// Portion of the usable screen area as unit fractions with a top-left origin; nil for positions that depend on the window.
    var fractions: CGRect? {
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .leftThird: return CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: return CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: return CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: return CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .center, .nextDisplay, .previousDisplay, .restore, .moveLeft, .moveRight, .moveUp, .moveDown: return nil
        }
    }

    func frame(in area: CGRect, gap: CGFloat) -> CGRect? {
        fractions.map { SnapGeometry.frame(fractions: $0, in: area, gap: gap) }
    }
}

/// A user-defined target; coordinates are unit fractions of the usable screen area, top-left origin.
struct CustomSnapArea: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var fractions: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    static func load() -> [CustomSnapArea] {
        (try? JSONDecoder().decode([CustomSnapArea].self, from: Prefs.shared.customSnapAreas)) ?? []
    }

    static func save(_ areas: [CustomSnapArea]) {
        if let data = try? JSONEncoder().encode(areas) { Prefs.shared.customSnapAreas = data }
    }
}

enum SnapGeometry {
    /// Maps unit fractions into `area`, leaving `gap` points between neighbouring windows and to the screen edges.
    static func frame(fractions f: CGRect, in area: CGRect, gap: CGFloat) -> CGRect {
        // Shrinking the area by half a gap and each cell by another half makes every seam exactly one gap wide.
        let inner = area.insetBy(dx: gap / 2, dy: gap / 2)
        let cell = CGRect(x: inner.minX + inner.width * f.minX, y: inner.minY + inner.height * f.minY,
                          width: inner.width * f.width, height: inner.height * f.height)
        return cell.insetBy(dx: gap / 2, dy: gap / 2).roundedEdges
    }

    /// Sizes a half-screen snap steps through when the same shortcut is pressed again: 1/2 → 2/3 → 1/3.
    static func cycle(for position: SnapPosition) -> [CGRect]? {
        let steps: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
        switch position {
        case .leftHalf: return steps.map { CGRect(x: 0, y: 0, width: $0, height: 1) }
        case .rightHalf: return steps.map { CGRect(x: 1 - $0, y: 0, width: $0, height: 1) }
        case .topHalf: return steps.map { CGRect(x: 0, y: 0, width: 1, height: $0) }
        case .bottomHalf: return steps.map { CGRect(x: 0, y: 1 - $0, width: 1, height: $0) }
        default: return nil
        }
    }

    /// The frame for `position`, advancing through its size cycle when the window already sits at one of the steps.
    static func nextFrame(for position: SnapPosition, current: CGRect, in area: CGRect, gap: CGFloat, cycling: Bool = true) -> CGRect? {
        guard cycling, let cycle = cycle(for: position) else { return position.frame(in: area, gap: gap) }
        let frames = cycle.map { frame(fractions: $0, in: area, gap: gap) }
        if let index = frames.firstIndex(where: { $0.isClose(to: current, tolerance: 8) }) { return frames[(index + 1) % frames.count] }
        return frames[0]
    }

    /// Pushes `frame` against one edge of `area` (keeping its size, shrunk only to fit) without moving it along that edge.
    static func moved(_ frame: CGRect, to position: SnapPosition, in area: CGRect, gap: CGFloat) -> CGRect? {
        let bounds = area.insetBy(dx: gap, dy: gap)
        let size = CGSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
        // Along the edge the window stays put, but is pulled back inside the area if it hangs off.
        var x = min(max(frame.minX, bounds.minX), bounds.maxX - size.width)
        var y = min(max(frame.minY, bounds.minY), bounds.maxY - size.height)
        switch position {
        case .moveLeft: x = bounds.minX
        case .moveRight: x = bounds.maxX - size.width
        case .moveUp: y = bounds.minY // top-left origin: smaller y is higher up
        case .moveDown: y = bounds.maxY - size.height
        default: return nil
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size).roundedEdges
    }

    /// Expresses `frame` as unit fractions of `area` (the inverse of `frame(fractions:in:gap:)` without gaps).
    static func fractions(of frame: CGRect, in area: CGRect) -> CGRect {
        guard area.width > 0, area.height > 0 else { return .zero }
        func unit(_ v: CGFloat) -> CGFloat { max(0, min(1, (v * 1000).rounded() / 1000)) }
        return CGRect(x: unit((frame.minX - area.minX) / area.width), y: unit((frame.minY - area.minY) / area.height),
                      width: unit(frame.width / area.width), height: unit(frame.height / area.height))
    }

    /// Same relative placement on another display; used when moving a window between screens.
    static func transfer(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let f = fractions(of: frame, in: source)
        return CGRect(x: target.minX + target.width * f.minX, y: target.minY + target.height * f.minY,
                      width: min(target.width, target.width * f.width), height: min(target.height, target.height * f.height)).roundedEdges
    }

    /// Which snap a dragged window should get for a pointer position (AppKit coordinates, y up).
    /// Edges snap to halves or maximize; the ends of each edge snap to quarters.
    static func position(forPointer p: CGPoint, in screen: CGRect, threshold: CGFloat = 6, corner: CGFloat = 140) -> SnapPosition? {
        guard screen.insetBy(dx: -1, dy: -1).contains(p) else { return nil }
        let left = p.x <= screen.minX + threshold, right = p.x >= screen.maxX - threshold
        let top = p.y >= screen.maxY - threshold, bottom = p.y <= screen.minY + threshold
        let nearTop = p.y >= screen.maxY - corner, nearBottom = p.y <= screen.minY + corner
        let nearLeft = p.x <= screen.minX + corner, nearRight = p.x >= screen.maxX - corner
        if left { return nearTop ? .topLeft : (nearBottom ? .bottomLeft : .leftHalf) }
        if right { return nearTop ? .topRight : (nearBottom ? .bottomRight : .rightHalf) }
        if top { return nearLeft ? .topLeft : (nearRight ? .topRight : .maximize) }
        if bottom { return nearLeft ? .bottomLeft : (nearRight ? .bottomRight : nil) }
        return nil
    }
}

extension CGRect {
    /// Rounds each edge to the nearest point. Unlike `integral` this never grows the rect past its neighbours,
    /// so tiles computed from fractions such as 0.7 stay seamless.
    var roundedEdges: CGRect {
        let x0 = minX.rounded(), y0 = minY.rounded()
        return CGRect(x: x0, y: y0, width: maxX.rounded() - x0, height: maxY.rounded() - y0)
    }
}
