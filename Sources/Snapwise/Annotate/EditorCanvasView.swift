import AppKit
import Combine
import SwiftUI

/// Interactive drawing surface. Works in image pixels; the scroll view supplies zooming.
final class EditorCanvasView: NSView, NSTextFieldDelegate {
    let model: EditorModel
    private var draft: Annotation?
    private var drag: DragMode?
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero
    /// The text annotation being re-edited; it is off the canvas until committed.
    private var editingOriginal: Annotation?
    private var subscription: AnyCancellable?

    private enum DragMode {
        case draw
        case move(last: CGPoint, recorded: Bool)
        /// `movesStart` picks which end of a line or arrow follows the mouse, so its direction is preserved.
        case resize(movesStart: Bool, recorded: Bool)
        case crop(start: CGPoint)
    }

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        syncSize()
        model.commitPendingEdits = { [weak self] in self?.commitText() }
        // objectWillChange fires before the value lands, so redraw on the next runloop turn.
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.syncSize()
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: model.tool == .select ? .arrow : (model.tool == .text ? .iBeam : .crosshair))
    }

    private var scale: CGFloat { model.scale }
    private var contentOrigin: CGPoint { model.layout.content.origin }
    /// Converts screen-constant sizes (handles, hit slop) into image pixels at the current zoom.
    private var pixelsPerPoint: CGFloat { scale / (enclosingScrollView?.magnification ?? 1) }

    private func syncSize() {
        let canvas = model.layout.canvas
        let size = CGSize(width: canvas.width / scale, height: canvas.height / scale)
        if frame.size != size { setFrameSize(size) }
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * scale - contentOrigin.x, y: p.y * scale - contentOrigin.y)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        AnnotationRenderer.drawComposition(state: model.state, background: model.background, scale: scale, in: ctx, draft: draft)
        ctx.translateBy(x: contentOrigin.x, y: contentOrigin.y)
        if let selected = model.selected { drawSelection(selected, in: ctx) }
        if let crop = model.cropRect { drawCrop(crop, in: ctx) }
        ctx.restoreGState()
    }

    private func handlePoints(for a: Annotation) -> [CGPoint] {
        if a.tool.isSegment { return [a.start, a.end] }
        if a.tool.isBox {
            let r = a.rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        }
        return []
    }

    private func drawSelection(_ a: Annotation, in ctx: CGContext) {
        let unit = pixelsPerPoint
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(unit)
        if !a.tool.isSegment {
            ctx.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit])
            ctx.stroke(a.bounds.insetBy(dx: -3 * unit, dy: -3 * unit))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        for p in handlePoints(for: a) {
            let rect = CGRect(x: p.x - 4.5 * unit, y: p.y - 4.5 * unit, width: 9 * unit, height: 9 * unit)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.strokeEllipse(in: rect)
        }
    }

    private func drawCrop(_ crop: CGRect, in ctx: CGContext) {
        let unit = pixelsPerPoint
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.addRect(model.imageBounds)
        ctx.addRect(crop)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(unit)
        ctx.stroke(crop)
        // Rule-of-thirds guides.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        for i in 1...2 {
            let x = crop.minX + crop.width * CGFloat(i) / 3, y = crop.minY + crop.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: crop.minY)); ctx.addLine(to: CGPoint(x: x, y: crop.maxY))
            ctx.move(to: CGPoint(x: crop.minX, y: y)); ctx.addLine(to: CGPoint(x: crop.maxX, y: y))
        }
        ctx.strokePath()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        let p = imagePoint(event)
        let slop = 6 * pixelsPerPoint

        // The selected annotation stays adjustable in every tool, so a fresh shape can be tweaked without switching.
        if model.tool != .crop, var a = model.selected {
            if let index = handlePoints(for: a).firstIndex(where: { $0.distance(to: p) <= slop * 1.5 }) {
                if a.tool.isSegment {
                    drag = .resize(movesStart: index == 0, recorded: false)
                } else {
                    // Re-anchor boxes so the dragged corner is always `end`; a box has no direction to preserve.
                    let corners = handlePoints(for: a)
                    a.start = corners[(index + 2) % 4]
                    a.end = corners[index]
                    model.update(a)
                    drag = .resize(movesStart: false, recorded: false)
                }
                return
            }
            if model.tool != .select, a.hitTest(p, tolerance: slop) {
                if event.clickCount == 2, a.tool == .text { return beginText(at: a.start, editing: a) }
                drag = .move(last: p, recorded: false)
                return
            }
        }

        switch model.tool {
        case .select:
            if let hit = model.annotation(at: p, tolerance: slop) {
                model.selectedID = hit.id
                if event.clickCount == 2, hit.tool == .text { return beginText(at: hit.start, editing: hit) }
                drag = .move(last: p, recorded: false)
            } else {
                model.selectedID = nil
            }
        case .crop:
            model.cropRect = nil
            drag = .crop(start: clampToImage(p))
        case .text:
            if let hit = model.annotation(at: p, tolerance: slop), hit.tool == .text {
                beginText(at: hit.start, editing: hit)
            } else {
                beginText(at: p, editing: nil)
            }
        case .counter:
            let counter = model.makeAnnotation(.counter, at: p)
            model.add(counter)
            model.selectedID = counter.id
        case .image:
            break
        default:
            model.selectedID = nil
            draft = model.makeAnnotation(model.tool, at: p)
            drag = .draw
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event)
        guard let mode = drag else { return }
        switch mode {
        case .draw:
            guard var a = draft else { return }
            if a.tool == .pencil {
                a.points.append(p)
                a.end = p
            } else {
                a.end = event.modifierFlags.contains(.shift) ? constrain(p, from: a.start, tool: a.tool) : p
            }
            draft = a
            needsDisplay = true
        case .move(let last, let recorded):
            guard var a = model.selected else { return }
            if !recorded { model.checkpoint() }
            a.translate(by: p - last)
            model.update(a)
            drag = .move(last: p, recorded: true)
        case .resize(let movesStart, let recorded):
            guard var a = model.selected else { return }
            if !recorded { model.checkpoint() }
            let anchor = movesStart ? a.end : a.start
            let target = event.modifierFlags.contains(.shift) ? constrain(p, from: anchor, tool: a.tool) : p
            if movesStart { a.start = target } else { a.end = target }
            model.update(a)
            drag = .resize(movesStart: movesStart, recorded: true)
        case .crop(let start):
            var end = clampToImage(p)
            if let ratio = model.cropAspectRatio {
                let w = abs(end.x - start.x), h = w / ratio
                end.y = start.y + (end.y < start.y ? -h : h)
            }
            model.cropRect = CGRect(from: start, to: end).intersection(model.imageBounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        guard case .draw = drag, let a = draft else { return }
        draft = nil
        needsDisplay = true
        let bigEnough = a.tool == .pencil ? a.points.count > 2 : a.start.distance(to: a.end) > 3 * pixelsPerPoint
        if bigEnough {
            model.add(a)
            model.selectedID = a.id
        }
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(model.state.size.width, p.x)), y: max(0, min(model.state.size.height, p.y)))
    }

    /// Shift-drag: squares for boxes, 45° steps for lines and arrows.
    private func constrain(_ p: CGPoint, from start: CGPoint, tool: Tool) -> CGPoint {
        let d = p - start
        if tool.isBox {
            let side = max(abs(d.x), abs(d.y))
            return CGPoint(x: start.x + (d.x < 0 ? -side : side), y: start.y + (d.y < 0 ? -side : side))
        }
        let angle = (atan2(d.y, d.x) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: start.x + cos(angle) * d.length, y: start.y + sin(angle) * d.length)
    }

    // MARK: - Text editing

    private func beginText(at origin: CGPoint, editing existing: Annotation?) {
        var fontSize = model.fontSize
        if let existing {
            // The annotation leaves the canvas while its text is in the field.
            model.checkpoint()
            model.remove(id: existing.id)
            model.selectedID = nil
            editingOriginal = existing
            fontSize = existing.fontSize / scale
        }
        textOrigin = origin
        let field = NSTextField(string: existing?.text ?? "")
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = (existing?.color ?? model.color).ns
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6)
        field.delegate = self
        field.placeholderString = "Text"
        field.sizeToFit()
        field.frame = CGRect(x: (origin.x + contentOrigin.x) / scale, y: (origin.y + contentOrigin.y) / scale,
                             width: max(80, field.frame.width + 12), height: field.frame.height)
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = textField else { return }
        let origin = field.frame.origin
        field.sizeToFit()
        field.frame = CGRect(origin: origin, size: CGSize(width: max(80, field.frame.width + 12), height: field.frame.height))
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil // cleared first: removing the field re-enters via controlTextDidEndEditing
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        let original = editingOriginal
        editingOriginal = nil
        guard !text.isEmpty else { return }
        var a = original ?? model.makeAnnotation(.text, at: textOrigin)
        a.text = text
        a.end = CGPoint(x: a.start.x + a.bounds.width, y: a.start.y + a.bounds.height)
        if original != nil {
            model.restore(a) // the checkpoint was taken when editing began
        } else {
            model.add(a)
        }
        model.selectedID = a.id
        window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard and menu actions

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 51, 117: model.deleteSelected()
        case 53:
            if model.cropRect != nil { model.cropRect = nil } else { model.selectedID = nil }
        case 36, 76:
            if model.tool == .crop { model.applyCrop() }
        case 123...126:
            guard var a = model.selected else { return }
            let step = (event.modifierFlags.contains(.shift) ? 10 : 1) * scale
            let deltas: [UInt16: CGPoint] = [123: CGPoint(x: -step, y: 0), 124: CGPoint(x: step, y: 0),
                                             125: CGPoint(x: 0, y: step), 126: CGPoint(x: 0, y: -step)]
            model.coalescedCheckpoint(for: a.id)
            a.translate(by: deltas[event.keyCode] ?? .zero)
            model.update(a)
        default:
            if modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(), let tool = Tool.shortcuts[key] {
                model.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    @objc func copy(_ sender: Any?) { model.onCopy?() }
    @objc func saveDocument(_ sender: Any?) { model.onSave?() }
    @objc func delete(_ sender: Any?) { model.deleteSelected() }

    @objc func paste(_ sender: Any?) {
        if let image = NSImage(pasteboard: .general)?.cgImage { model.addImage(image) }
    }

    // MARK: - Dropping images to combine them

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSImage.canInit(with: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let image = NSImage(pasteboard: sender.draggingPasteboard)?.cgImage else { return false }
        let p = convert(sender.draggingLocation, from: nil)
        model.addImage(image, at: CGPoint(x: p.x * scale - contentOrigin.x, y: p.y * scale - contentOrigin.y))
        window?.makeFirstResponder(self)
        return true
    }
}

/// Keeps a document smaller than the viewport centered instead of pinned to a corner.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

final class EditorScrollView: NSScrollView {
    private var didFit = false
    var onZoomChanged: ((CGFloat) -> Void)?

    override var magnification: CGFloat {
        didSet { onZoomChanged?(magnification) }
    }

    // Pinch gestures bypass the property setter.
    override func setMagnification(_ magnification: CGFloat, centeredAt point: NSPoint) {
        super.setMagnification(magnification, centeredAt: point)
        onZoomChanged?(self.magnification)
    }

    override func layout() {
        super.layout()
        guard !didFit, documentView != nil, contentSize.width > 50 else { return }
        didFit = true
        apply(.fit)
    }

    func apply(_ command: ZoomCommand) {
        guard let document = documentView, document.frame.width > 0 else { return }
        let target: CGFloat
        switch command {
        case .zoomIn: target = magnification * 1.25
        case .zoomOut: target = magnification / 1.25
        case .actual: target = 1
        case .fit:
            // contentSize shrinks with magnification, so measure the unmagnified viewport.
            let viewport = CGSize(width: frame.width - 2, height: frame.height - 2)
            target = min(1, min(viewport.width / document.frame.width, viewport.height / document.frame.height) * 0.92)
        }
        let center = CGPoint(x: documentVisibleRect.midX, y: documentVisibleRect.midY)
        setMagnification(max(minMagnification, min(maxMagnification, target)), centeredAt: center)
    }
}

struct EditorCanvas: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> EditorScrollView {
        let scroll = EditorScrollView()
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        scroll.documentView = EditorCanvasView(model: model)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 12
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.onZoomChanged = { [weak model] zoom in
            // Reported during layout; publishing must wait for the next runloop turn.
            DispatchQueue.main.async { if model?.zoom != zoom { model?.zoom = zoom } }
        }
        model.zoomCommand = { [weak scroll] in scroll?.apply($0) }
        return scroll
    }

    func updateNSView(_ nsView: EditorScrollView, context: Context) {}
}
