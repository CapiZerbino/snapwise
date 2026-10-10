import AVFoundation
import CoreImage

struct VideoExportOptions: Equatable {
    var start: Double = 0
    var end: Double = 0
    /// original | 16:9 | 1:1 | 9:16
    var format = "original"
    /// Index into `GradientPreset.all`, or -1 for no backdrop.
    var backgroundIndex = -1
    /// Fraction of the canvas' short side left around the video.
    var padding = 0.06
    var cornerRadius = 14.0
    var zoomOnClicks = false
    var zoomScale = 1.8
    var mute = false
    /// 0 keeps the source resolution.
    var maxHeight = 0

    var usesCanvas: Bool { backgroundIndex >= 0 || format != "original" }
}

/// Computes the camera for auto-zoom: where to look and how far in, for a given time.
enum ClickZoom {
    static func state(at t: Double, clicks: [ClickEvent], maxScale: Double, ramp: Double = 0.45, hold: Double = 1.6) -> (scale: Double, x: Double, y: Double) {
        var best = 0.0, weightSum = 0.0, x = 0.0, y = 0.0
        for click in clicks {
            let intensity: Double
            if t < click.t - ramp || t > click.t + hold + ramp {
                continue
            } else if t < click.t {
                intensity = (t - (click.t - ramp)) / ramp
            } else if t <= click.t + hold {
                intensity = 1
            } else {
                intensity = 1 - (t - click.t - hold) / ramp
            }
            best = max(best, intensity)
            // Blending overlapping clicks by weight pans smoothly from one to the next.
            let weight = intensity * intensity
            weightSum += weight
            x += click.x * weight
            y += click.y * weight
        }
        guard weightSum > 0 else { return (1, 0.5, 0.5) }
        let eased = best * best * (3 - 2 * best)
        return (1 + (maxScale - 1) * eased, x / weightSum, y / weightSum)
    }
}

enum VideoExporter {
    struct Layout: Equatable {
        let canvas: CGSize
        let content: CGRect
    }

    /// Output size and where the video sits inside it.
    static func layout(natural: CGSize, options: VideoExportOptions) -> Layout {
        var canvas = natural
        if let ratio = ["16:9": 16.0 / 9, "1:1": 1.0, "9:16": 9.0 / 16][options.format] {
            if natural.width / natural.height > ratio {
                canvas.height = natural.width / ratio
            } else {
                canvas.width = natural.height * ratio
            }
        }
        let k = options.maxHeight > 0 ? min(1, CGFloat(options.maxHeight) / canvas.height) : 1
        canvas = RecordingManager.encodableSize(CGSize(width: canvas.width * k, height: canvas.height * k))
        guard options.usesCanvas else { return Layout(canvas: canvas, content: CGRect(origin: .zero, size: canvas)) }
        let inset = options.backgroundIndex >= 0 ? min(canvas.width, canvas.height) * options.padding : 0
        let fitted = Geo.aspectFit(natural, in: CGSize(width: canvas.width - inset * 2, height: canvas.height - inset * 2))
        return Layout(canvas: canvas, content: CGRect(x: (canvas.width - fitted.width) / 2, y: (canvas.height - fitted.height) / 2,
                                                      width: fitted.width, height: fitted.height))
    }

    /// Builds the per-frame effect pipeline; also used for live preview in the editor.
    static func composition(asset: AVAsset, options: VideoExportOptions, clicks: [ClickEvent]) async throws -> AVVideoComposition {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
        let natural = try await track.load(.naturalSize)
        let layout = layout(natural: natural, options: options)
        let canvasRect = CGRect(origin: .zero, size: layout.canvas)
        let radius = options.backgroundIndex >= 0 ? options.cornerRadius * Double(layout.content.width / natural.width) : 0

        var backdrop = CIImage(color: .black).cropped(to: canvasRect)
        var shadow: CIImage?
        if options.backgroundIndex >= 0 {
            let preset = GradientPreset.at(options.backgroundIndex)
            backdrop = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: canvasRect.height), "inputPoint1": CIVector(x: canvasRect.width, y: 0),
                "inputColor0": CIColor(cgColor: preset.colors[0]), "inputColor1": CIColor(cgColor: preset.colors[1]),
            ])?.outputImage?.cropped(to: canvasRect) ?? backdrop
            shadow = roundedRect(layout.content, radius: radius, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.45))?
                .applyingGaussianBlur(sigma: Double(layout.canvas.height) * 0.018)
        }
        let background = shadow?.composited(over: backdrop).cropped(to: canvasRect) ?? backdrop
        let mask = radius > 0 ? roundedRect(layout.content, radius: radius, color: .white) : nil
        let source = CGRect(origin: .zero, size: natural)

        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            var frame = request.sourceImage
            if options.zoomOnClicks, !clicks.isEmpty {
                let zoom = ClickZoom.state(at: request.compositionTime.seconds, clicks: clicks, maxScale: options.zoomScale)
                if zoom.scale > 1.001 {
                    let s = CGFloat(zoom.scale)
                    let view = CGSize(width: source.width / s, height: source.height / s)
                    // Core Image's y axis points up; click coordinates are top-left based.
                    let vx = max(0, min(source.width - view.width, CGFloat(zoom.x) * source.width - view.width / 2))
                    let vy = max(0, min(source.height - view.height, CGFloat(1 - zoom.y) * source.height - view.height / 2))
                    frame = frame.transformed(by: CGAffineTransform(translationX: -vx, y: -vy))
                        .transformed(by: CGAffineTransform(scaleX: s, y: s)).cropped(to: source)
                }
            }
            let k = layout.content.width / source.width
            var output = frame.transformed(by: CGAffineTransform(scaleX: k, y: layout.content.height / source.height))
                .transformed(by: CGAffineTransform(translationX: layout.content.minX, y: layout.content.minY))
            if options.usesCanvas {
                if let mask {
                    output = output.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
                } else {
                    output = output.composited(over: background)
                }
            }
            request.finish(with: output.cropped(to: canvasRect), context: nil)
        }
        composition.renderSize = layout.canvas
        return composition
    }

    private static func roundedRect(_ rect: CGRect, radius: Double, color: CIColor) -> CIImage? {
        CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect), "inputRadius": radius, "inputColor": color,
        ])?.outputImage
    }

    static func export(asset: AVAsset, options: VideoExportOptions, clicks: [ClickEvent], to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.videoComposition = try await composition(asset: asset, options: options, clicks: clicks)
        session.timeRange = CMTimeRange(start: CMTime(seconds: options.start, preferredTimescale: 600),
                                        end: CMTime(seconds: options.end, preferredTimescale: 600))
        if options.mute {
            let mix = AVMutableAudioMix()
            mix.inputParameters = try await asset.loadTracks(withMediaType: .audio).map {
                let parameters = AVMutableAudioMixInputParameters(track: $0)
                parameters.setVolume(0, at: .zero)
                return parameters
            }
            session.audioMix = mix
        }
        try await session.export(to: url, as: .mp4)
    }
}
