import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Image formats and tools, all through ImageIO / Core Graphics / Vision.
enum ImageConversions {
    enum Failure: LocalizedError {
        case unreadable(String), unwritable(String), nothingFound

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Could not read \(name)"
            case .unwritable(let ext): return "Could not write \(ext.uppercased())"
            case .nothingFound: return "Nothing found in the image"
            }
        }
    }

    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw Failure.unreadable(url.lastPathComponent) }
        return oriented(image, orientation: orientation(of: source))
    }

    static func convert(_ url: URL, to ext: String) throws -> URL {
        let output = ConversionCatalog.output(for: url, ext: ext)
        try write(try load(url), to: output, ext: ext)
        return output
    }

    /// Encodes `image` as `ext`. Formats without transparency get a white background instead of black.
    static func write(_ image: CGImage, to url: URL, ext: String, quality: Double = 0.9) throws {
        if ext == "pdf" { return try writePDF([image], to: url) }
        var image = image
        if ["jpg", "bmp"].contains(ext) { image = flattened(image) }
        if ext == "ico" { image = squared(image, side: 256) }
        if ext == "icns" { image = squared(image, side: 512) } // ImageIO writes ICNS up to 512 px
        let type = (ext == "jpg" ? UTType.jpeg : UTType(filenameExtension: ext))?.identifier ?? ext
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { throw Failure.unwritable(ext) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unwritable(ext) }
    }

    /// One page per image, each page the size of its image.
    static func writePDF(_ images: [CGImage], to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw Failure.unwritable("pdf")
        }
        for image in images {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
        }
        context.closePDF()
    }

    // MARK: - Tools

    static func run(_ tool: FileTool, on urls: [URL]) throws -> [URL] {
        if tool == .combineIntoPDF {
            let first = urls[0]
            let output = ConversionCatalog.freeURL(in: first.deletingLastPathComponent(), base: "Combined", ext: "pdf")
            try writePDF(try urls.map(load), to: output)
            return [output]
        }
        return try urls.map { url in
            let image = try load(url)
            let ext = ConversionCatalog.normalized(url.pathExtension)
            switch tool {
            case .compressImage:
                // Keep transparency when there is any; otherwise JPEG is the most compatible small format.
                let target = hasAlpha(image) ? "heic" : "jpg"
                let output = ConversionCatalog.output(for: url, ext: target, suffix: "compressed")
                try write(image, to: output, ext: target, quality: 0.6)
                return output
            case .resizeHalf:
                return try save(scaled(image, by: 0.5), like: url, ext: ext, suffix: "50%")
            case .rotate:
                return try save(transformed(image, rotate: true), like: url, ext: ext, suffix: "rotated")
            case .flip:
                return try save(transformed(image, rotate: false), like: url, ext: ext, suffix: "flipped")
            case .stripMetadata:
                // Re-encoding from pixels only drops EXIF, GPS and other properties.
                return try save(image, like: url, ext: ext, suffix: "no metadata")
            case .removeBackground:
                let output = ConversionCatalog.output(for: url, ext: "png", suffix: "cut out")
                try write(try removeBackground(image), to: output, ext: "png")
                return output
            default:
                return url
            }
        }
    }

    private static func save(_ image: CGImage, like source: URL, ext: String, suffix: String) throws -> URL {
        // Formats ImageIO can read but not write (e.g. WebP, SVG) come out as PNG.
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains((UTType(filenameExtension: ext) ?? .png).identifier)
        let target = writable ? ext : "png"
        let output = ConversionCatalog.output(for: source, ext: target, suffix: suffix)
        try write(image, to: output, ext: target)
        return output
    }

    /// Subject lift (Vision): keeps the foreground objects and makes everything else transparent.
    static func removeBackground(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first else { throw Failure.nothingFound }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let result = CIContext().createCGImage(ci, from: ci.extent) else { throw Failure.nothingFound }
        return result
    }

    // MARK: - Pixel helpers

    private static func orientation(of source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyOrientation] as? Int ?? 1
    }

    /// Applies the EXIF orientation so the pixels are upright before re-encoding (re-encoding drops the tag).
    private static func oriented(_ image: CGImage, orientation: Int) -> CGImage {
        guard orientation != 1 else { return image }
        let ci = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation))
        return CIContext().createCGImage(ci, from: ci.extent) ?? image
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        body(context)
        return context.makeImage()
    }

    static func flattened(_ image: CGImage) -> CGImage {
        draw(width: image.width, height: image.height) { context in
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        } ?? image
    }

    static func scaled(_ image: CGImage, by factor: CGFloat) -> CGImage {
        let width = max(1, Int(CGFloat(image.width) * factor)), height = max(1, Int(CGFloat(image.height) * factor))
        return draw(width: width, height: height) { $0.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) } ?? image
    }

    /// Centres the image on a transparent square canvas, as icon formats require.
    private static func squared(_ image: CGImage, side: Int) -> CGImage {
        draw(width: side, height: side) { context in
            let fit = Geo.aspectFit(CGSize(width: image.width, height: image.height), in: CGSize(width: side, height: side))
            context.draw(image, in: CGRect(x: (CGFloat(side) - fit.width) / 2, y: (CGFloat(side) - fit.height) / 2, width: fit.width, height: fit.height))
        } ?? image
    }

    /// 90° clockwise rotation, or a horizontal mirror.
    private static func transformed(_ image: CGImage, rotate: Bool) -> CGImage {
        let w = image.width, h = image.height
        return draw(width: rotate ? h : w, height: rotate ? w : h) { context in
            if rotate {
                context.translateBy(x: 0, y: CGFloat(w))
                context.rotate(by: -.pi / 2)
            } else {
                context.translateBy(x: CGFloat(w), y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        } ?? image
    }
}
