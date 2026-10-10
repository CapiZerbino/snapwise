import AppKit

struct RGBA: Codable, Equatable, Hashable {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .red
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }

    init(hex: String) { self.init(NSColor(hex: hex)) }

    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { ns.cgColor }

    static let palette: [RGBA] = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE", "#FFFFFF", "#000000"].map(RGBA.init(hex:))
}

enum Tool: String, CaseIterable, Codable {
    case select, crop, arrow, rect, filledRect, ellipse, line, pencil, highlighter, text, counter, blur, spotlight
    /// An image dropped into the editor; not offered in the toolbar.
    case image

    static let toolbar: [Tool] = [.select, .crop, .arrow, .rect, .filledRect, .ellipse, .line, .pencil, .highlighter, .text, .counter, .blur, .spotlight]

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .filledRect: return "rectangle.fill"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .counter: return "1.circle.fill"
        case .blur: return "drop.halffull"
        case .spotlight: return "flashlight.on.fill"
        case .image: return "photo"
        }
    }

    var title: String {
        switch self {
        case .select: return "Select (V)"
        case .crop: return "Crop (X)"
        case .arrow: return "Arrow (A)"
        case .rect: return "Rectangle (R)"
        case .filledRect: return "Filled Rectangle (F)"
        case .ellipse: return "Ellipse (O)"
        case .line: return "Line (L)"
        case .pencil: return "Pencil (P)"
        case .highlighter: return "Highlighter (H)"
        case .text: return "Text (T)"
        case .counter: return "Counter (C)"
        case .blur: return "Blur / Pixelate (B)"
        case .spotlight: return "Spotlight (S)"
        case .image: return "Image"
        }
    }

    static let shortcuts: [String: Tool] = ["v": .select, "x": .crop, "a": .arrow, "r": .rect, "f": .filledRect, "o": .ellipse,
                                            "l": .line, "p": .pencil, "h": .highlighter, "t": .text, "c": .counter, "b": .blur, "s": .spotlight]

    /// Shapes defined by two corner points.
    var isBox: Bool { [.rect, .filledRect, .ellipse, .blur, .spotlight, .image].contains(self) }
    /// Shapes defined by two end points.
    var isSegment: Bool { [.line, .arrow, .highlighter].contains(self) }
}

enum ArrowStyle: String, CaseIterable, Codable {
    case standard, thin, tapered, curved
}

enum TextStyle: String, CaseIterable, Codable {
    case plain, outlined, filled, whiteBox, darkBox, mono, shadowed

    var label: String {
        switch self {
        case .plain: return "Plain"
        case .outlined: return "Outlined"
        case .filled: return "Filled"
        case .whiteBox: return "White Box"
        case .darkBox: return "Dark Box"
        case .mono: return "Monospace"
        case .shadowed: return "Shadow"
        }
    }
}

enum BlurStyle: String, CaseIterable, Codable {
    case pixelate, smooth, secure
}

/// One editable mark. All geometry is in image pixels with a top-left origin.
struct Annotation: Codable, Identifiable, Equatable {
    var id = UUID()
    var tool: Tool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var color: RGBA
    var lineWidth: CGFloat
    var text = ""
    var fontSize: CGFloat = 32
    var textStyle: TextStyle = .plain
    var arrowStyle: ArrowStyle = .standard
    var blurStyle: BlurStyle = .pixelate
    var number = 1
    var imageData: Data?

    var rect: CGRect { CGRect(from: start, to: end) }

    var counterRadius: CGFloat { fontSize * 0.85 }

    /// Bounding box used for selection outlines.
    var bounds: CGRect {
        switch tool {
        case .pencil:
            guard let first = points.first else { return .zero }
            return points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        case .counter:
            return CGRect(x: start.x - counterRadius, y: start.y - counterRadius, width: counterRadius * 2, height: counterRadius * 2)
        case .text:
            return CGRect(origin: start, size: AnnotationRenderer.textSize(for: self))
        default:
            return rect
        }
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = tolerance + lineWidth / 2
        switch tool {
        case .line, .arrow, .highlighter:
            return p.distance(toSegment: start, end) <= reach
        case .pencil:
            return zip(points, points.dropFirst()).contains { p.distance(toSegment: $0, $1) <= reach }
        case .rect, .ellipse:
            // Outlines are grabbed by their stroke so shapes underneath stay reachable.
            let outer = rect.insetBy(dx: -reach, dy: -reach)
            let inner = rect.insetBy(dx: reach, dy: reach)
            return outer.contains(p) && (inner.isEmpty || inner.width <= 0 || inner.height <= 0 || !inner.contains(p))
        default:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    mutating func translate(by d: CGPoint) {
        start = start + d
        end = end + d
        points = points.map { $0 + d }
    }
}

/// What the undo stack snapshots: the pixels plus every mark on top of them.
struct EditorState {
    var base: CGImage
    var annotations: [Annotation]

    var size: CGSize { CGSize(width: base.width, height: base.height) }
}
