import AppKit

struct BackgroundLayout: Equatable {
    /// Full output size in pixels.
    let canvas: CGSize
    /// Where the screenshot sits inside the canvas (top-left origin).
    let content: CGRect
}

/// The backdrop placed behind a screenshot. Lengths are in points and scale with the image's Retina factor.
struct BackgroundSettings: Codable, Equatable {
    var enabled = false
    /// gradient | solid | image
    var kind = "gradient"
    var gradientIndex = 0
    var solid = RGBA(hex: "#FFFFFF")
    var imageData: Data?
    var padding: CGFloat = 56
    var cornerRadius: CGFloat = 10
    var shadow: CGFloat = 0.5
    var aspect = "auto"
    /// 0...8, row-major from top-left; 4 is centered.
    var alignment = 4

    static let aspects = ["auto", "1:1", "4:3", "3:2", "16:9", "9:16"]

    private var aspectRatio: CGFloat? {
        let parts = aspect.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 && parts[1] > 0 ? CGFloat(parts[0] / parts[1]) : nil
    }

    func layout(imageSize: CGSize, scale: CGFloat) -> BackgroundLayout {
        guard enabled else { return BackgroundLayout(canvas: imageSize, content: CGRect(origin: .zero, size: imageSize)) }
        let pad = (padding * scale).rounded()
        var canvas = CGSize(width: imageSize.width + pad * 2, height: imageSize.height + pad * 2)
        if let ratio = aspectRatio {
            // Only ever grow the canvas so the screenshot is never scaled or clipped.
            if canvas.width / canvas.height < ratio {
                canvas.width = (canvas.height * ratio).rounded()
            } else {
                canvas.height = (canvas.width / ratio).rounded()
            }
        }
        let column = CGFloat(alignment % 3), row = CGFloat(alignment / 3)
        let origin = CGPoint(x: ((canvas.width - imageSize.width) * column / 2).rounded(),
                             y: ((canvas.height - imageSize.height) * row / 2).rounded())
        return BackgroundLayout(canvas: canvas, content: CGRect(origin: origin, size: imageSize))
    }

    // MARK: - Presets

    static func loadPresets() -> [BackgroundSettings] {
        (try? JSONDecoder().decode([BackgroundSettings].self, from: Prefs.shared.backgroundPresets)) ?? []
    }

    static func savePresets(_ presets: [BackgroundSettings]) {
        if let data = try? JSONEncoder().encode(presets) { Prefs.shared.backgroundPresets = data }
    }
}

enum AutoBalance {
    /// Finds a crop that equalizes the uniform margins around a screenshot's content, or nil when already balanced.
    static func balancedCrop(of image: CGImage, tolerance: Int = 8) -> CGRect? {
        let w = image.width, h = image.height
        guard w > 8, h > 8, let ctx = CGContext.bitmap(width: w, height: h), let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytesPerRow = ctx.bytesPerRow
        let px = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * h)
        // The bitmap's first row in memory is the top of the image.
        let bg = (px[0], px[1], px[2])

        func matches(_ x: Int, _ y: Int) -> Bool {
            let i = y * bytesPerRow + x * 4
            return abs(Int(px[i]) - Int(bg.0)) <= tolerance && abs(Int(px[i + 1]) - Int(bg.1)) <= tolerance && abs(Int(px[i + 2]) - Int(bg.2)) <= tolerance
        }
        func columnIsBackground(_ x: Int) -> Bool { stride(from: 0, to: h, by: 2).allSatisfy { matches(x, $0) } }
        func rowIsBackground(_ y: Int) -> Bool { stride(from: 0, to: w, by: 2).allSatisfy { matches($0, y) } }

        var left = 0, right = 0, top = 0, bottom = 0
        while left < w - 1, columnIsBackground(left) { left += 1 }
        guard left < w - 1 else { return nil } // a blank image has nothing to balance
        while right < w - 1 - left, columnIsBackground(w - 1 - right) { right += 1 }
        while top < h - 1, rowIsBackground(top) { top += 1 }
        while bottom < h - 1 - top, rowIsBackground(h - 1 - bottom) { bottom += 1 }

        let mx = min(left, right), my = min(top, bottom)
        let crop = CGRect(x: left - mx, y: top - my, width: w - (left - mx) - (right - mx), height: h - (top - my) - (bottom - my))
        return crop.size == CGSize(width: w, height: h) ? nil : crop
    }
}
