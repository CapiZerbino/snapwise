import AVFoundation
import ScreenCaptureKit

/// Streams a ScreenCaptureKit filter into an H.264/AAC MP4 file, with pause support.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Settings {
        var pixelSize: CGSize
        var sourceRect: CGRect?
        var fps: Int
        var bitrate: Int
        var showCursor: Bool
        var systemAudio: Bool
        var microphone: Bool
    }

    let url: URL
    var onError: ((Error) -> Void)?

    private var stream: SCStream!
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "com.tieuviettrongnghia.lumshot.recorder")
    private let frameDuration: CMTime

    // Accessed only on `queue`.
    private var sessionStarted = false
    private var paused = false
    private var pauseStart = CMTime.invalid
    /// Total paused time, subtracted from every timestamp so the file has no gap.
    private var offset = CMTime.zero
    private var lastVideoPTS = CMTime.invalid
    /// Last timestamp written per input; writers reject buffers that go backwards.
    private var lastAppended: [ObjectIdentifier: CMTime] = [:]
    private(set) var failure: Error?

    init(filter: SCContentFilter, settings: Settings, url: URL) throws {
        self.url = url
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.fps))

        let config = SCStreamConfiguration()
        config.width = Int(settings.pixelSize.width)
        config.height = Int(settings.pixelSize.height)
        if let rect = settings.sourceRect { config.sourceRect = rect }
        config.minimumFrameInterval = frameDuration
        config.showsCursor = settings.showCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.capturesAudio = settings.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.captureMicrophone = settings.microphone

        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitrate,
                AVVideoExpectedSourceFrameRateKey: settings.fps,
                AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        func makeAudioInput(channels: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 64_000 * channels,
            ])
            input.expectsMediaDataInRealTime = true
            return input
        }
        if settings.systemAudio {
            let input = makeAudioInput(channels: 2)
            writer.add(input)
            audioInput = input
        }
        if settings.microphone {
            let input = makeAudioInput(channels: 1)
            writer.add(input)
            micInput = input
        }

        super.init()
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if settings.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if settings.microphone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
    }

    func start() async throws {
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        try await stream.startCapture()
    }

    func setPaused(_ value: Bool) {
        queue.async {
            guard self.paused != value else { return }
            self.paused = value
            // Stream timestamps are on the host clock, so the paused span can be measured directly.
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            if value {
                self.pauseStart = now
            } else if self.pauseStart.isValid {
                self.offset = self.offset + (now - self.pauseStart)
                self.pauseStart = .invalid
            }
        }
    }

    /// Stops capturing and finalizes the file. Returns nil when nothing was recorded.
    func stop() async -> URL? {
        try? await stream.stopCapture()
        return await withCheckedContinuation { continuation in
            queue.async {
                guard self.sessionStarted, self.writer.status == .writing else {
                    self.failure = self.writer.error
                    self.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.url)
                    return continuation.resume(returning: nil)
                }
                // Idle screens deliver no frames; extend the last one up to the moment recording stopped (or was paused).
                let stopTime = (self.paused && self.pauseStart.isValid ? self.pauseStart : CMClockGetTime(CMClockGetHostTimeClock())) - self.offset
                if self.lastVideoPTS.isValid, stopTime > self.lastVideoPTS { self.writer.endSession(atSourceTime: stopTime) }
                self.videoInput.markAsFinished()
                self.audioInput?.markAsFinished()
                self.micInput?.markAsFinished()
                self.writer.finishWriting {
                    self.failure = self.writer.error
                    continuation.resume(returning: self.writer.status == .completed ? self.url : nil)
                }
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, writer.status == .writing, !paused else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            let pts = sampleBuffer.presentationTimeStamp - offset
            if !sessionStarted {
                writer.startSession(atSourceTime: pts)
                sessionStarted = true
            }
            if append(sampleBuffer, to: videoInput) { lastVideoPTS = pts }
        case .audio:
            if sessionStarted, let audioInput { append(sampleBuffer, to: audioInput) }
        case .microphone:
            if sessionStarted, let micInput { append(sampleBuffer, to: micInput) }
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }

    @discardableResult
    private func append(_ buffer: CMSampleBuffer, to input: AVAssetWriterInput) -> Bool {
        guard input.isReadyForMoreMediaData, let retimed = retime(buffer) else { return false }
        let pts = retimed.presentationTimeStamp
        // Buffers queued across a pause boundary can land before ones already written.
        if let last = lastAppended[ObjectIdentifier(input)], pts <= last { return false }
        guard input.append(retimed) else { return false }
        lastAppended[ObjectIdentifier(input)] = pts
        return true
    }

    /// Abandons a recording that never started capturing.
    func cancel() {
        queue.async {
            self.writer.cancelWriting()
            try? FileManager.default.removeItem(at: self.url)
        }
    }

    private func retime(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard offset != .zero else { return buffer }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for i in 0..<count {
            timing[i].presentationTimeStamp = timing[i].presentationTimeStamp - offset
            if timing[i].decodeTimeStamp.isValid { timing[i].decodeTimeStamp = timing[i].decodeTimeStamp - offset }
        }
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy
    }
}

enum GIFExporter {
    /// Samples a video at `fps` and writes a looping GIF no wider than `maxWidth`.
    static func export(videoURL: URL, to output: URL, fps: Int, maxWidth: Int, timeRange: CMTimeRange? = nil) async throws {
        let asset = AVURLAsset(url: videoURL)
        let range: CMTimeRange
        if let timeRange { range = timeRange } else { range = CMTimeRange(start: .zero, duration: try await asset.load(.duration)) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)

        let count = max(1, Int(range.duration.seconds * Double(fps)))
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "com.compuserve.gif" as CFString, count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = 1.0 / Double(fps)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for index in 0..<count {
            let time = range.start + CMTime(seconds: Double(index) * delay, preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
