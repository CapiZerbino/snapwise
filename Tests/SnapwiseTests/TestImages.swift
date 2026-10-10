import CoreGraphics
import Foundation
@testable import Snapwise

/// Deterministic generator so image-based tests are reproducible.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt8 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8(truncatingIfNeeded: state >> 33)
    }
}

enum TestImages {
    /// Builds an image from a pixel function; `(0, 0)` is the top-left pixel.
    static func make(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let i = (y * width + x) * 4
                data[i] = r; data[i + 1] = g; data[i + 2] = b
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func solid(width: Int, height: Int, _ color: (UInt8, UInt8, UInt8)) -> CGImage {
        make(width: width, height: height) { _, _ in color }
    }

    /// Blocky noise: every line differs from its neighbours along both axes, like real page content.
    static func noise(width: Int, height: Int, seed: UInt64, block: Int = 6) -> CGImage {
        var random = SeededRandom(seed: seed)
        let columns = width / block + 1, rows = height / block + 1
        let values = (0..<(columns * rows)).map { _ in random.next() }
        return make(width: width, height: height) { x, y in
            let v = values[(y / block) * columns + x / block]
            return (v, v, v)
        }
    }

    /// RGBA bytes with the top row first.
    static func pixels(of image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    static func color(in image: CGImage, x: Int, y: Int) -> (Int, Int, Int) {
        let data = pixels(of: image)
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    static func crop(_ image: CGImage, x: Int, y: Int, width: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: x, y: y, width: width, height: height))!
    }

    /// Largest per-channel difference between two same-sized images.
    static func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        guard pa.count == pb.count else { return 255 }
        return zip(pa, pb).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    /// Stacks images vertically (all must share a width).
    static func stack(_ images: [CGImage]) -> CGImage {
        let width = images[0].width
        let rows = images.flatMap { image -> [[UInt8]] in
            let data = pixels(of: image)
            return (0..<image.height).map { Array(data[($0 * width * 4)..<(($0 + 1) * width * 4)]) }
        }
        return make(width: width, height: rows.count) { x, y in (rows[y][x * 4], rows[y][x * 4 + 1], rows[y][x * 4 + 2]) }
    }

    /// Mirrors rows and columns so a vertical scroll fixture becomes a horizontal one.
    static func transpose(_ image: CGImage) -> CGImage {
        let data = pixels(of: image)
        return make(width: image.height, height: image.width) { x, y in
            let i = (x * image.width + y) * 4
            return (data[i], data[i + 1], data[i + 2])
        }
    }
}
