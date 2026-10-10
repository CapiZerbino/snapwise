import AppKit
import CoreImage

/// Draws editor content. Every entry point expects a context whose origin is the image's
/// top-left corner with y pointing down and one unit per pixel, so the on-screen canvas and exports share one code path.
enum AnnotationRenderer {
    private static let ciContext = CIContext()
    private static var blurCache: [String: CGImage] = [:]
    private static var imageCache: [UUID: CGImage] = [:]

    // MARK: - Output

    static func flatten(_ state: EditorState) -> CGImage {
        render(size: state.size) { draw(state: state, in: $0) } ?? state.base
    }

    static func export(state: EditorState, background: BackgroundSettings, scale: CGFloat) -> CGImage {
        guard background.enabled else { return flatten(state) }
        let layout = background.layout(imageSize: state.size, scale: scale)
        return render(size: layout.canvas) {
            drawComposition(state: state, background: background, scale: scale, in: $0)
        } ?? state.base
    }

    private static func render(size: CGSize, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext.bitmap(width: Int(size.width), height: Int(size.height)) else { return nil }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        body(ctx)
        return ctx.makeImage()
    }

    // MARK: - Composition

    /// Draws the backdrop (when enabled) and the annotated screenshot on top of it.
    static func drawComposition(state: EditorState, background: BackgroundSettings, scale: CGFloat, in ctx: CGContext, draft: Annotation? = nil) {
        guard background.enabled else { return draw(state: state, in: ctx, draft: draft) }
        let layout = background.layout(imageSize: state.size, scale: scale)
        let canvas = CGRect(origin: .zero, size: layout.canvas)
        switch background.kind {
        case "solid":
            ctx.setFillColor(background.solid.cg)
            ctx.fill(canvas)
        case "image":
            if let data = background.imageData, let image = NSImage(data: data)?.cgImage {
                let s = max(canvas.width / CGFloat(image.width), canvas.height / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * s, height: CGFloat(image.height) * s)
                ctx.saveGState()
                ctx.clip(to: canvas)
                ctx.drawFlipped(image, in: CGRect(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2, width: size.width, height: size.height))
                ctx.restoreGState()
            }
        default:
            GradientPreset.at(background.gradientIndex).fill(canvas, in: ctx)
        }

        let radius = min(background.cornerRadius * scale, min(layout.content.width, layout.content.height) / 2)
        let shape = CGPath(roundedRect: layout.content, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if background.shadow > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 40 * scale * background.shadow, color: NSColor.black.withAlphaComponent(0.25 + 0.35 * background.shadow).cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(shape)
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.translateBy(x: layout.content.minX, y: layout.content.minY)
        draw(state: state, in: ctx, draft: draft)
        ctx.restoreGState()
    }

    /// Draws the base image and all annotations. Blur and spotlight sample or cover the base, so they go first.
    static func draw(state: EditorState, in ctx: CGContext, draft: Annotation? = nil) {
        let full = CGRect(origin: .zero, size: state.size)
        ctx.drawFlipped(state.base, in: full)
        let all = state.annotations + (draft.map { [$0] } ?? [])

        for a in all where a.tool == .blur {
            if let image = blurred(base: state.base, rect: a.rect, style: a.blurStyle) {
                ctx.drawFlipped(image, in: a.rect.intersection(full).integral)
            }
        }
        let spotlights = all.filter { $0.tool == .spotlight }
        if !spotlights.isEmpty {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.addRect(full)
            spotlights.forEach { ctx.addRect($0.rect.intersection(full)) }
            ctx.fillPath(using: .evenOdd)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        for a in all where a.tool != .blur && a.tool != .spotlight { draw(a, in: ctx) }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Shapes

    private static func draw(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(a.color.cg)
        ctx.setFillColor(a.color.cg)
        ctx.setLineWidth(a.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.tool {
        case .rect:
            ctx.setLineJoin(.miter)
            ctx.stroke(a.rect)
        case .filledRect:
            ctx.fill(a.rect)
        case .ellipse:
            ctx.strokeEllipse(in: a.rect)
        case .line:
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()
        case .highlighter:
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(a.color.ns.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(a.lineWidth * 4)
            ctx.setLineCap(.butt)
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()
        case .pencil:
            ctx.addPath(smoothPath(a.points))
            ctx.strokePath()
        case .arrow:
            drawArrow(a, in: ctx)
        case .counter:
            let r = a.counterRadius
            ctx.fillEllipse(in: CGRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2))
            let luminance = 0.299 * a.color.r + 0.587 * a.color.g + 0.114 * a.color.b
            let str = NSAttributedString(string: "\(a.number)", attributes: [
                .font: NSFont.systemFont(ofSize: a.fontSize, weight: .bold),
                .foregroundColor: luminance > 0.7 ? NSColor.black : NSColor.white,
            ])
            let size = str.size()
            str.draw(at: CGPoint(x: a.start.x - size.width / 2, y: a.start.y - size.height / 2))
        case .text:
            drawText(a, in: ctx)
        case .image:
            if let image = decodedImage(for: a) { ctx.drawFlipped(image, in: a.rect) }
        case .select, .crop, .blur, .spotlight:
            break
        }
    }

    /// Smooths freehand input by curving through the midpoints of consecutive samples.
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private static func drawArrow(_ a: Annotation, in ctx: CGContext) {
        let v = a.end - a.start
        let length = v.length
        guard length > 1 else { return }
        var u = v * (1 / length)
        let head = min(max(a.lineWidth * 4.5, 14), length * 0.6)
        let headWidth = head * 0.8
        let normal = CGPoint(x: -u.y, y: u.x)

        switch a.arrowStyle {
        case .standard:
            ctx.move(to: a.start)
            ctx.addLine(to: a.end - u * (head * 0.8))
            ctx.strokePath()
        case .thin:
            ctx.setLineWidth(max(1, a.lineWidth * 0.6))
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()
            ctx.move(to: a.end - u * head + normal * (headWidth / 2))
            ctx.addLine(to: a.end)
            ctx.addLine(to: a.end - u * head - normal * (headWidth / 2))
            ctx.strokePath()
            return
        case .tapered:
            let base = a.end - u * (head * 0.9)
            ctx.move(to: a.start)
            ctx.addLine(to: base + normal * (a.lineWidth * 0.9))
            ctx.addLine(to: base - normal * (a.lineWidth * 0.9))
            ctx.closePath()
            ctx.fillPath()
        case .curved:
            let mid = CGPoint(x: (a.start.x + a.end.x) / 2, y: (a.start.y + a.end.y) / 2)
            let control = mid + normal * (length * 0.22)
            let tangent = a.end - control
            u = tangent * (1 / max(tangent.length, 0.001))
            ctx.move(to: a.start)
            ctx.addQuadCurve(to: a.end - u * (head * 0.8), control: control)
            ctx.strokePath()
        }
        let n = CGPoint(x: -u.y, y: u.x)
        ctx.move(to: a.end)
        ctx.addLine(to: a.end - u * head + n * (headWidth / 2))
        ctx.addLine(to: a.end - u * head - n * (headWidth / 2))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Text

    private static func isBoxed(_ style: TextStyle) -> Bool { [.filled, .whiteBox, .darkBox].contains(style) }

    private static func textPadding(for a: Annotation) -> CGFloat { isBoxed(a.textStyle) ? a.fontSize * 0.35 : 0 }

    static func attributedText(for a: Annotation) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: a.textStyle == .mono ? NSFont.monospacedSystemFont(ofSize: a.fontSize, weight: .semibold)
                : NSFont.systemFont(ofSize: a.fontSize, weight: .semibold),
            .foregroundColor: a.textStyle == .filled || a.textStyle == .darkBox ? NSColor.white : a.color.ns,
        ]
        if a.textStyle == .shadowed {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = a.fontSize * 0.18
            shadow.shadowOffset = CGSize(width: 0, height: -a.fontSize * 0.06)
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: a.text.isEmpty ? " " : a.text, attributes: attributes)
    }

    static func textSize(for a: Annotation) -> CGSize {
        let size = attributedText(for: a).size()
        let pad = textPadding(for: a)
        return CGSize(width: ceil(size.width) + pad * 2, height: ceil(size.height) + pad * 2)
    }

    private static func drawText(_ a: Annotation, in ctx: CGContext) {
        let pad = textPadding(for: a)
        if isBoxed(a.textStyle) {
            let box = CGRect(origin: a.start, size: textSize(for: a))
            let fill: NSColor = a.textStyle == .filled ? a.color.ns : (a.textStyle == .whiteBox ? .white : NSColor.black.withAlphaComponent(0.82))
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: a.fontSize * 0.3, cornerHeight: a.fontSize * 0.3, transform: nil))
            ctx.fillPath()
        }
        let origin = CGPoint(x: a.start.x + pad, y: a.start.y + pad)
        let text = attributedText(for: a)
        if a.textStyle == .outlined {
            // Stroke first and fill on top, so the halo never eats into the glyphs.
            let halo = NSMutableAttributedString(attributedString: text)
            halo.addAttributes([.strokeColor: NSColor.white, .strokeWidth: 14.0, .foregroundColor: NSColor.white],
                               range: NSRange(location: 0, length: halo.length))
            ctx.setLineJoin(.round)
            halo.draw(at: origin)
        }
        text.draw(at: origin)
    }

    // MARK: - Pixel effects

    private static func decodedImage(for a: Annotation) -> CGImage? {
        if let cached = imageCache[a.id] { return cached }
        guard let data = a.imageData, let image = NSImage(data: data)?.cgImage else { return nil }
        imageCache[a.id] = image
        return image
    }

    /// Returns the obscured pixels for `rect` (image space, top-left origin), clipped to the image.
    static func blurred(base: CGImage, rect: CGRect, style: BlurStyle) -> CGImage? {
        let r = rect.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height)).integral
        guard r.width >= 2, r.height >= 2 else { return nil }
        let key = "\(Unmanaged.passUnretained(base).toOpaque())|\(r)|\(style.rawValue)"
        if let cached = blurCache[key] { return cached }

        let source = CIImage(cgImage: base).clampedToExtent()
        let ciRect = CGRect(x: r.minX, y: CGFloat(base.height) - r.maxY, width: r.width, height: r.height)
        let shortSide = min(r.width, r.height)
        let output: CIImage
        switch style {
        case .pixelate:
            output = source.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: max(8, shortSide / 10), kCIInputCenterKey: CIVector(x: ciRect.minX, y: ciRect.minY),
            ])
        case .smooth:
            output = source.applyingGaussianBlur(sigma: max(8, shortSide / 10))
        case .secure:
            // Coarse blocks followed by a blur leave no recoverable glyph shapes.
            let block = max(18, shortSide / 4)
            output = source.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: block, kCIInputCenterKey: CIVector(x: ciRect.minX, y: ciRect.minY),
            ]).applyingGaussianBlur(sigma: block / 2)
        }
        guard let image = ciContext.createCGImage(output, from: ciRect) else { return nil }
        if blurCache.count > 48 { blurCache.removeAll() } // dragging a blur creates one entry per mouse move
        blurCache[key] = image
        return image
    }
}
