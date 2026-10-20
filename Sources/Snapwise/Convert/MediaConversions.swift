import AVFoundation
import ImageIO

/// Video and audio conversions through AVFoundation.
enum MediaConversions {
    enum Failure: LocalizedError {
        case unsupported(String), noAudio, exportFailed

        var errorDescription: String? {
            switch self {
            case .unsupported(let name): return "\(name) can't be converted by macOS"
            case .noAudio: return "The file has no audio"
            case .exportFailed: return "Export failed"
            }
        }
    }

    static func convert(_ url: URL, to ext: String) async throws -> URL {
        let output = ConversionCatalog.output(for: url, ext: ext)
        switch ext {
        case "gif":
            try await GIFExporter.export(videoURL: url, to: output, fps: Prefs.shared.gifFPS, maxWidth: Prefs.shared.gifMaxWidth)
        case "m4a":
            try await export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: output)
        case "mp4", "mov":
            // Passthrough keeps the original quality when the codecs fit the new container, re-encoding otherwise.
            let type: AVFileType = ext == "mp4" ? .mp4 : .mov
            do { try await export(url, preset: AVAssetExportPresetPassthrough, type: type, to: output) } catch {
                try? FileManager.default.removeItem(at: output)
                try await export(url, preset: AVAssetExportPresetHighestQuality, type: type, to: output)
            }
        default:
            try transcodeAudio(url, to: output, ext: ext)
        }
        return output
    }

    static func run(_ tool: FileTool, on url: URL) async throws -> URL {
        switch tool {
        case .compressVideo:
            let output = ConversionCatalog.output(for: url, ext: "mp4", suffix: "compressed")
            try await export(url, preset: AVAssetExportPresetHEVC1920x1080, type: .mp4, to: output)
            return output
        case .downscale720:
            let output = ConversionCatalog.output(for: url, ext: "mp4", suffix: "720p")
            try await export(url, preset: AVAssetExportPreset1280x720, type: .mp4, to: output)
            return output
        case .mute:
            let asset = AVURLAsset(url: url)
            let composition = AVMutableComposition()
            let duration = try await asset.load(.duration)
            for track in try await asset.loadTracks(withMediaType: .video) {
                let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                try copy?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                copy?.preferredTransform = try await track.load(.preferredTransform)
            }
            let ext = url.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
            let output = ConversionCatalog.output(for: url, ext: ext, suffix: "muted")
            try await export(composition, preset: AVAssetExportPresetPassthrough, type: ext == "mov" ? .mov : .mp4, to: output)
            return output
        case .extractFrame:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            let frame = try await generator.image(at: .zero).image
            let output = ConversionCatalog.output(for: url, ext: "png", suffix: "frame")
            try ImageConversions.write(frame, to: output, ext: "png")
            return output
        default:
            return url
        }
    }

    private static func export(_ url: URL, preset: String, type: AVFileType, to output: URL) async throws {
        try await export(AVURLAsset(url: url), preset: preset, type: type, to: output, name: url.lastPathComponent)
    }

    private static func export(_ asset: AVAsset, preset: String, type: AVFileType, to output: URL, name: String = "The file") async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset),
              try await session.compatibleFileTypes.contains(type) || preset == AVAssetExportPresetPassthrough
        else { throw Failure.unsupported(name) }
        try await session.export(to: output, as: type)
    }

    /// Lossless and uncompressed formats: decode to PCM, write with AVAudioFile.
    private static func transcodeAudio(_ url: URL, to output: URL, ext: String) throws {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: url) } catch { throw Failure.unsupported(url.lastPathComponent) }
        let format = input.processingFormat
        var settings: [String: Any] = [AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount]
        switch ext {
        case "flac":
            settings[AVFormatIDKey] = kAudioFormatFLAC
        default:
            // WAV, AIFF and CAF as 16-bit PCM; AIFF is big-endian by definition.
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = ext == "aiff"
        }
        let file = try AVAudioFile(forWriting: output, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else { throw Failure.exportFailed }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try file.write(from: buffer)
        }
    }
}
