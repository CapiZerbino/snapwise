import AppKit
import Combine

final class EditorModel: ObservableObject {
    @Published private(set) var state: EditorState
    @Published private(set) var undoStack: [EditorState] = []
    @Published private(set) var redoStack: [EditorState] = []
    @Published var tool: Tool = .arrow {
        didSet {
            if tool != .crop { cropRect = nil }
            if tool != .select { selectedID = nil }
        }
    }
    // Style controls, in points; multiplied by `scale` when a mark is created.
    @Published var color = RGBA.palette[0] { didSet { applyStyleToSelection() } }
    @Published var lineWidth: CGFloat = 4 { didSet { applyStyleToSelection() } }
    @Published var fontSize: CGFloat = 18 { didSet { applyStyleToSelection() } }
    @Published var arrowStyle: ArrowStyle = .standard { didSet { applyStyleToSelection() } }
    @Published var textStyle: TextStyle = .plain { didSet { applyStyleToSelection() } }
    @Published var blurStyle: BlurStyle = .pixelate { didSet { applyStyleToSelection() } }
    @Published var selectedID: UUID? { didSet { loadStyleFromSelection() } }
    @Published var background = BackgroundSettings() { didSet { if background != oldValue { isDirty = true } } }
    @Published var cropRect: CGRect?
    @Published var cropAspect = "free"
    @Published var showInspector = false
    /// Current canvas magnification, reported by the scroll view.
    @Published var zoom: CGFloat = 1
    var zoomCommand: ((ZoomCommand) -> Void)?

    /// Pixels per point of the source capture.
    let scale: CGFloat
    private(set) var isDirty = false
    private var syncingStyle = false
    /// Annotation whose current run of style/nudge tweaks already has an undo entry, so a slider drag is one step.
    private var coalescingID: UUID?
    /// Lets the canvas flush an open text field before state is replaced or exported.
    var commitPendingEdits: (() -> Void)?

    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?

    init(image: CGImage, scale: CGFloat, annotations: [Annotation] = [], background: BackgroundSettings = BackgroundSettings()) {
        state = EditorState(base: image, annotations: annotations)
        self.scale = max(1, scale)
        self.background = background
        isDirty = false
    }

    var layout: BackgroundLayout { background.layout(imageSize: state.size, scale: scale) }
    var selected: Annotation? { state.annotations.first { $0.id == selectedID } }
    var imageBounds: CGRect { CGRect(origin: .zero, size: state.size) }

    // MARK: - Undo

    /// Records the current state; call once before a user-visible change.
    func checkpoint() {
        coalescingID = nil
        undoStack.append(state)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack = []
        isDirty = true
    }

    /// Like `checkpoint`, but consecutive calls for the same annotation share one undo entry.
    func coalescedCheckpoint(for id: UUID) {
        guard coalescingID != id else { return }
        checkpoint()
        coalescingID = id
    }

    func undo() {
        commitPendingEdits?()
        coalescingID = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
        selectedID = nil
    }

    func redo() {
        commitPendingEdits?()
        coalescingID = nil
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        selectedID = nil
    }

    func markSaved() { isDirty = false }

    // MARK: - Annotations

    func makeAnnotation(_ tool: Tool, at p: CGPoint) -> Annotation {
        var a = Annotation(tool: tool, start: p, end: p, color: color, lineWidth: lineWidth * scale)
        a.fontSize = fontSize * scale
        a.textStyle = textStyle
        a.arrowStyle = arrowStyle
        a.blurStyle = blurStyle
        if tool == .pencil { a.points = [p] }
        if tool == .counter { a.number = (state.annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1 }
        return a
    }

    func add(_ a: Annotation) {
        checkpoint()
        state.annotations.append(a)
    }

    /// Replaces an annotation in place without touching the undo stack (used while dragging).
    func update(_ a: Annotation) {
        guard let i = state.annotations.firstIndex(where: { $0.id == a.id }) else { return }
        state.annotations[i] = a
    }

    /// Puts back an annotation that was lifted off the canvas for editing; the caller already took a checkpoint.
    func restore(_ a: Annotation) {
        if let i = state.annotations.firstIndex(where: { $0.id == a.id }) {
            state.annotations[i] = a
        } else {
            state.annotations.append(a)
        }
    }

    func remove(id: UUID) {
        state.annotations.removeAll { $0.id == id }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        checkpoint()
        remove(id: id)
        selectedID = nil
    }

    func annotation(at p: CGPoint, tolerance: CGFloat) -> Annotation? {
        state.annotations.last { $0.tool != .spotlight && $0.hitTest(p, tolerance: tolerance) }
            ?? state.annotations.last { $0.hitTest(p, tolerance: tolerance) }
    }

    func addImage(_ image: CGImage, at center: CGPoint? = nil) {
        guard let data = image.encoded(as: .png) else { return }
        let fitted = Geo.aspectFit(image.size, in: CGSize(width: min(image.size.width, state.size.width * 0.6),
                                                          height: min(image.size.height, state.size.height * 0.6)))
        let c = center ?? imageBounds.center
        var a = makeAnnotation(.image, at: CGPoint(x: c.x - fitted.width / 2, y: c.y - fitted.height / 2))
        a.end = CGPoint(x: a.start.x + fitted.width, y: a.start.y + fitted.height)
        a.imageData = data
        add(a)
        tool = .select
        selectedID = a.id
    }

    private func applyStyleToSelection() {
        guard !syncingStyle, var a = selected else { return }
        a.color = color
        a.lineWidth = lineWidth * scale
        a.fontSize = fontSize * scale
        a.arrowStyle = arrowStyle
        a.textStyle = textStyle
        a.blurStyle = blurStyle
        guard a != selected else { return }
        coalescedCheckpoint(for: a.id)
        update(a)
    }

    private func loadStyleFromSelection() {
        coalescingID = nil
        guard let a = selected else { return }
        syncingStyle = true
        color = a.color
        lineWidth = a.lineWidth / scale
        fontSize = a.fontSize / scale
        arrowStyle = a.arrowStyle
        textStyle = a.textStyle
        blurStyle = a.blurStyle
        syncingStyle = false
    }

    // MARK: - Image operations

    var cropAspectRatio: CGFloat? {
        let parts = cropAspect.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 && parts[1] > 0 ? CGFloat(parts[0] / parts[1]) : nil
    }

    func applyCrop() {
        guard let rect = cropRect?.intersection(imageBounds).integral, rect.width >= 2, rect.height >= 2 else { return }
        crop(to: rect)
        cropRect = nil
    }

    private func crop(to rect: CGRect) {
        guard let cropped = state.base.cropping(to: rect) else { return }
        checkpoint()
        let shift = CGPoint(x: -rect.minX, y: -rect.minY)
        state = EditorState(base: cropped, annotations: state.annotations.map {
            var a = $0
            a.translate(by: shift)
            return a
        })
    }

    func autoBalance() {
        guard let rect = AutoBalance.balancedCrop(of: state.base) else { return Toast.show("Already balanced") }
        crop(to: rect)
    }

    /// Rotation, flipping and resizing bake the annotations into the pixels first.
    private func transform(newSize: CGSize, _ apply: (CGContext, CGImage) -> Void) {
        let flat = AnnotationRenderer.flatten(state)
        guard let ctx = CGContext.bitmap(width: Int(newSize.width), height: Int(newSize.height)) else { return }
        ctx.interpolationQuality = .high
        apply(ctx, flat)
        guard let image = ctx.makeImage() else { return }
        checkpoint()
        state = EditorState(base: image, annotations: [])
        selectedID = nil
    }

    func rotate(clockwise: Bool) {
        let w = state.size.width, h = state.size.height
        transform(newSize: CGSize(width: h, height: w)) { ctx, image in
            if clockwise {
                ctx.translateBy(x: 0, y: w)
                ctx.rotate(by: -.pi / 2)
            } else {
                ctx.translateBy(x: h, y: 0)
                ctx.rotate(by: .pi / 2)
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    func flip(horizontal: Bool) {
        let w = state.size.width, h = state.size.height
        transform(newSize: state.size) { ctx, image in
            if horizontal {
                ctx.translateBy(x: w, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            } else {
                ctx.translateBy(x: 0, y: h)
                ctx.scaleBy(x: 1, y: -1)
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    func resize(toWidth width: CGFloat) {
        guard width >= 1, width != state.size.width else { return }
        let size = CGSize(width: width.rounded(), height: (state.size.height * width / state.size.width).rounded())
        transform(newSize: size) { ctx, image in ctx.draw(image, in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: - Output

    func exported() -> CGImage {
        commitPendingEdits?()
        return AnnotationRenderer.export(state: state, background: background, scale: scale)
    }
}

/// Editable document: the untouched pixels plus annotations and backdrop, so work can be resumed later.
struct ProjectFile: Codable {
    static let fileExtension = "snapwise"
    /// Includes the extension used before the app was renamed.
    static let readableExtensions = ["snapwise", "lumshot"]

    var version = 1
    var scale: CGFloat
    var basePNG: Data
    var annotations: [Annotation]
    var background: BackgroundSettings

    static func write(_ model: EditorModel, to url: URL) throws {
        guard let png = model.state.base.encoded(as: .png) else { throw CocoaError(.fileWriteUnknown) }
        let file = ProjectFile(scale: model.scale, basePNG: png, annotations: model.state.annotations, background: model.background)
        try JSONEncoder().encode(file).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> EditorModel {
        let file = try JSONDecoder().decode(ProjectFile.self, from: Data(contentsOf: url))
        guard let image = NSImage(data: file.basePNG)?.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        return EditorModel(image: image, scale: file.scale, annotations: file.annotations, background: file.background)
    }
}
