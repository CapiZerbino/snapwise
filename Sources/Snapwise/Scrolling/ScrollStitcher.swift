import CoreGraphics

/// Joins successive frames of a scrolling area into one long image.
///
/// Each frame is reduced to a strip of grayscale "lines" (rows for vertical scrolling, columns for horizontal).
/// The scroll distance between two frames is the shift that best aligns their lines; only the newly revealed
/// lines are kept. Lines that never move (sticky headers/footers) are detected once and emitted a single time.
struct ScrollStitcher {
    enum Axis { case vertical, horizontal }

    private struct Signature {
        let lines: Int
        let width: Int
        let data: [UInt8]
    }

    private struct Piece {
        let image: CGImage
        /// Line range of `image` contributed to the result.
        let range: Range<Int>
    }

    private(set) var axis: Axis?
    private var pieces: [Piece] = []
    private var first: CGImage?
    private var last: CGImage?
    private var previous: Signature?
    private var header = 0
    private var footer = 0
    private let sampleWidth = 48

    /// Lines appended after the first frame; lets callers show progress.
    private(set) var addedLines = 0

    init(axis: Axis? = nil) {
        self.axis = axis
    }

    /// Feeds the next frame. Returns true when it extended the result.
    @discardableResult
    mutating func add(_ image: CGImage) -> Bool {
        guard let first else {
            self.first = image
            last = image
            previous = axis.map { signature(of: image, axis: $0) }
            return true
        }
        guard image.width == first.width, image.height == first.height else { return false }

        // The direction is unknown until the content first moves: try both.
        for candidate in axis.map({ [$0] }) ?? [.vertical, .horizontal] {
            let prev = axis == nil ? signature(of: last ?? first, axis: candidate) : (previous ?? signature(of: first, axis: candidate))
            let current = signature(of: image, axis: candidate)
            if pieces.isEmpty {
                let fixed = fixedMargins(prev, current)
                header = fixed.header
                footer = fixed.footer
            }
            guard let shift = bestShift(from: prev, to: current) else { continue }
            if pieces.isEmpty {
                axis = candidate
                pieces.append(Piece(image: first, range: 0..<(prev.lines - footer)))
            }
            pieces.append(Piece(image: image, range: (current.lines - footer - shift)..<(current.lines - footer)))
            addedLines += shift
            previous = current
            last = image
            return true
        }
        return false
    }

    /// The stitched image, or the first frame when nothing scrolled.
    func result() -> CGImage? {
        guard let first, let last, let axis, !pieces.isEmpty else { return first }
        let lines = axis == .vertical ? first.height : first.width
        var all = pieces
        if footer > 0 { all.append(Piece(image: last, range: (lines - footer)..<lines)) }
        let total = all.reduce(0) { $0 + $1.range.count }
        let width = axis == .vertical ? first.width : total
        let height = axis == .vertical ? total : first.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return first }
        var offset = 0
        for piece in all {
            let crop = axis == .vertical
                ? CGRect(x: 0, y: piece.range.lowerBound, width: first.width, height: piece.range.count)
                : CGRect(x: piece.range.lowerBound, y: 0, width: piece.range.count, height: first.height)
            if let strip = piece.image.cropping(to: crop) {
                // Bitmap contexts have a bottom-left origin; vertical pieces are laid out from the top down.
                let rect = axis == .vertical
                    ? CGRect(x: 0, y: height - offset - piece.range.count, width: width, height: piece.range.count)
                    : CGRect(x: offset, y: 0, width: piece.range.count, height: height)
                ctx.draw(strip, in: rect)
            }
            offset += piece.range.count
        }
        return ctx.makeImage()
    }

    // MARK: - Matching

    private func signature(of image: CGImage, axis: Axis) -> Signature {
        let lines = axis == .vertical ? image.height : image.width
        let w = axis == .vertical ? sampleWidth : image.width
        let h = axis == .vertical ? image.height : sampleWidth
        var pixels = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            ctx?.interpolationQuality = .low
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard axis == .horizontal else { return Signature(lines: lines, width: sampleWidth, data: pixels) }
        // Transpose so each "line" is one image column.
        var transposed = [UInt8](repeating: 0, count: w * h)
        for x in 0..<w {
            for y in 0..<h { transposed[x * sampleWidth + y] = pixels[y * w + x] }
        }
        return Signature(lines: lines, width: sampleWidth, data: transposed)
    }

    /// Mean absolute difference between line `i` of `a` and line `j` of `b`.
    private func lineDifference(_ a: Signature, _ i: Int, _ b: Signature, _ j: Int) -> Int {
        var sum = 0
        a.data.withUnsafeBufferPointer { pa in
            b.data.withUnsafeBufferPointer { pb in
                let oa = i * a.width, ob = j * b.width
                for k in 0..<a.width { sum += abs(Int(pa[oa + k]) - Int(pb[ob + k])) }
            }
        }
        return sum / a.width
    }

    /// Leading and trailing lines that are identical in both frames, capped so a real scroll band always remains.
    private func fixedMargins(_ a: Signature, _ b: Signature) -> (header: Int, footer: Int) {
        let cap = a.lines / 3
        var header = 0, footer = 0
        while header < cap, lineDifference(a, header, b, header) <= 2 { header += 1 }
        while footer < cap, lineDifference(a, a.lines - 1 - footer, b, b.lines - 1 - footer) <= 2 { footer += 1 }
        return (header, footer)
    }

    /// How many lines the content advanced from `a` to `b`, or nil when it did not move or cannot be aligned.
    private func bestShift(from a: Signature, to b: Signature) -> Int? {
        let top = header, bottom = a.lines - footer
        let band = bottom - top
        guard band > 16 else { return nil }
        let step = max(1, band / 160)
        let rows = Array(stride(from: top, to: bottom, by: step))

        // Unchanged frame: nothing to add.
        let still = rows.reduce(0) { $0 + lineDifference(a, $1, b, $1) } / rows.count
        if still <= 1 { return nil }
        // A band without detail aligns at every shift, so no shift can be trusted.
        let detail = rows.dropFirst().reduce(0) { $0 + lineDifference(b, $1, b, $1 - step) } / max(1, rows.count - 1)
        if detail < 1 { return nil }

        var bestShift = 0, bestScore = Int.max
        let minOverlap = max(8, band / 6)
        for shift in 1...(band - minOverlap) {
            var sum = 0, count = 0
            var row = top
            // Once the running total exceeds what the best shift scored overall, this one cannot win.
            let planned = (bottom - shift - top + step - 1) / step
            let budget = bestScore == Int.max ? Int.max : (bestScore + 1) * planned
            while row + shift < bottom, sum <= budget {
                sum += lineDifference(a, row + shift, b, row)
                count += 1
                row += step
            }
            guard count >= 4, row + shift >= bottom else { continue }
            let score = sum / count
            if score < bestScore {
                bestScore = score
                bestShift = shift
                if score == 0 { break }
            }
        }
        return bestScore <= 6 && bestShift > 0 ? bestShift : nil
    }
}
