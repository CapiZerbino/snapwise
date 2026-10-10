import AppKit

/// Built-in two-stop gradients shared by the background tool, window screenshots and the video editor.
struct GradientPreset {
    let from: String
    let to: String
    let angle: CGFloat

    static let all: [GradientPreset] = [
        .init(from: "#FF9A8B", to: "#FF6A88", angle: 45), .init(from: "#FFE29F", to: "#FF719A", angle: 45),
        .init(from: "#F6D365", to: "#FDA085", angle: 30), .init(from: "#FBC2EB", to: "#A6C1EE", angle: 45),
        .init(from: "#A18CD1", to: "#FBC2EB", angle: 60), .init(from: "#84FAB0", to: "#8FD3F4", angle: 45),
        .init(from: "#43E97B", to: "#38F9D7", angle: 30), .init(from: "#4FACFE", to: "#00F2FE", angle: 45),
        .init(from: "#667EEA", to: "#764BA2", angle: 45), .init(from: "#30CFD0", to: "#330867", angle: 60),
        .init(from: "#5EE7DF", to: "#B490CA", angle: 45), .init(from: "#F093FB", to: "#F5576C", angle: 45),
        .init(from: "#FA709A", to: "#FEE140", angle: 30), .init(from: "#0BA360", to: "#3CBA92", angle: 45),
        .init(from: "#2B5876", to: "#4E4376", angle: 45), .init(from: "#141E30", to: "#243B55", angle: 60),
        .init(from: "#232526", to: "#414345", angle: 45), .init(from: "#E0EAFC", to: "#CFDEF3", angle: 45),
        .init(from: "#FDFBFB", to: "#EBEDEE", angle: 90), .init(from: "#FF0844", to: "#FFB199", angle: 45),
    ]

    static func at(_ index: Int) -> GradientPreset { all[max(0, min(all.count - 1, index))] }

    var colors: [CGColor] { [NSColor(hex: from).cgColor, NSColor(hex: to).cgColor] }

    /// Fills `rect` so both stops reach the rect's corners regardless of angle.
    func fill(_ rect: CGRect, in ctx: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) else { return }
        let rad = angle * .pi / 180
        let dx = cos(rad), dy = sin(rad)
        let half = (abs(dx) * rect.width + abs(dy) * rect.height) / 2
        let c = rect.center
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient, start: CGPoint(x: c.x - dx * half, y: c.y - dy * half),
                               end: CGPoint(x: c.x + dx * half, y: c.y + dy * half),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
}
