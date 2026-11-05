import AudioToolbox
import AVFoundation
import IOSurface
import Metal
import UniformTypeIdentifiers

// @unchecked: the writer, its receivers, `audio` and the step queue are touched only on `queue`; the pool is Sendable.
final class SegmentWriter: @unchecked Sendable {
    static let pixelHeight = 1080
    private static let videoBitRate = 10_000_000
    private static let audioBitRate = 128_000
    /// Frames the pool may hold at once; past it a frame is skipped at the source instead of queued.
    private static let poolLimit = 8
    private static let retryDelay = DispatchTimeInterval.milliseconds(4)

    private struct Frame {
        let sequence: UInt64
        let clipNs: UInt64
        let buffer: CVReadOnlyPixelBuffer
        var rendered: Bool?
    }

    private enum Step {
        case frame(Frame)
        case audio(endingAt: UInt64)
        case pad([UInt64])
        case resume
        case finish(@Sendable () -> Void)

        var isReady: Bool {
            guard case .frame(let frame) = self else { return true }
            return frame.rendered != nil
        }
    }

    private struct Picture {
        let buffer: CVReadOnlyPixelBuffer
        let clipNs: UInt64
    }

    private enum Append {
        case audio(ClipAudio.Buffer)
        case video(Picture)
    }

    let width: Int
    let replay = ReplayBuffer()
    private let queue = DispatchQueue(label: "io.corelift.Cartridge.capture", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput.PixelBufferReceiver
    private let sound: AVAssetWriterInput.SampleBufferReceiver
    private let pool: CVMutablePixelBuffer.Pool
    private var audio: ClipAudio
    private var steps: [Step] = []
    private var appends: [Append] = []
    private var retryScheduled = false
    private var lastBuffer: CVReadOnlyPixelBuffer?
    private var lastSequence: UInt64?
    private var failed = false

    init(width: Int, tap: SessionAudioTap?) throws(CaptureError) {
        self.width = width
        do {
            audio = try ClipAudio(tap: tap)
        } catch {
            PlayLog.session.error("capture-audio-format-failed \(error.localizedDescription)")
            throw .encoderFailed
        }
        guard let outputRate = Self.encodeRate(nearest: Double(audio.sampleRate)) else {
            PlayLog.session.error("capture-aac-rates-unavailable")
            throw .encoderFailed
        }
        writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(value: 1, timescale: 1)
        writer.initialSegmentStartTime = .zero
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(width: width))
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(rate: outputRate))
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            PlayLog.session.error("capture-inputs-refused w=\(width)")
            throw .encoderFailed
        }
        var attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: width, height: Self.pixelHeight),
            compatibility: [.metalTexture]
        )
        attributes.backing = .ioSurface
        video = writer.inputPixelBufferReceiver(for: videoInput, pixelBufferAttributes: attributes)
        sound = writer.inputReceiver(for: audioInput)
        writer.delegate = replay
        do {
            try writer.start()
        } catch {
            PlayLog.session.error("capture-writer-start-failed \(error.localizedDescription)")
            throw .encoderFailed
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = video.pixelBufferPool else {
            PlayLog.session.error("capture-pool-unavailable")
            writer.cancelWriting()
            throw .encoderFailed
        }
        self.pool = pool
    }

    func target(sequence: UInt64, clipNs: UInt64, device: any MTLDevice) -> CaptureTarget? {
        let buffer: CVReadOnlyPixelBuffer
        do {
            buffer = try CVReadOnlyPixelBuffer(pool.makeMutablePixelBuffer(.init(allocationThreshold: Self.poolLimit)))
        } catch {
            return nil
        }
        guard let texture = buffer.renderTexture(device: device) else { return nil }
        queue.async {
            self.steps.append(.frame(Frame(sequence: sequence, clipNs: clipNs, buffer: buffer)))
        }
        return CaptureTarget(texture: texture) { rendered in
            self.queue.async { self.markRendered(sequence, rendered) }
        }
    }

    func pad(times: [UInt64], contentEndNs: UInt64) {
        enqueue(.audio(endingAt: contentEndNs))
        enqueue(.pad(times))
    }

    func resume() {
        enqueue(.resume)
    }

    func finish(contentEndNs: UInt64?) async {
        if let contentEndNs {
            enqueue(.audio(endingAt: contentEndNs))
        }
        await withCheckedContinuation { continuation in
            enqueue(.finish { continuation.resume() })
        }
    }

    func cancel() {
        queue.async {
            self.steps.removeAll()
            self.appends.removeAll()
            self.writer.cancelWriting()
            self.replay.end()
        }
    }

    private func enqueue(_ step: Step) {
        queue.async {
            self.steps.append(step)
            self.drain()
        }
    }

    private func markRendered(_ sequence: UInt64, _ rendered: Bool) {
        if let index = steps.firstIndex(where: { step in
            guard case .frame(let frame) = step else { return false }
            return frame.sequence == sequence
        }), case .frame(var frame) = steps[index] {
            frame.rendered = rendered
            steps[index] = .frame(frame)
        }
        drain()
    }

    private func drain() {
        do {
            while try flushAppends(), let step = steps.first, step.isReady {
                steps.removeFirst()
                if failed {
                    if case .finish(let done) = step {
                        done()
                    }
                    continue
                }
                perform(step)
            }
        } catch {
            fail(error)
            drain()
        }
    }

    private func perform(_ step: Step) {
        switch step {
        case .frame(let frame):
            guard frame.rendered == true else { return }
            appends += audio.buffers(before: frame.sequence, startingAt: frame.clipNs).map(Append.audio)
            appends.append(.video(Picture(buffer: frame.buffer, clipNs: frame.clipNs)))
            lastBuffer = frame.buffer
            lastSequence = frame.sequence
        case .audio(let endNs):
            guard let lastSequence else { return }
            appends += audio.buffers(through: lastSequence, endingAt: endNs).map(Append.audio)
        case .pad(let times):
            guard let lastBuffer, let lastTime = times.last else { return }
            appends += audio.silence(until: lastTime + ClipClock.coreFrameNs).map(Append.audio)
            appends += times.map { .video(Picture(buffer: lastBuffer, clipNs: $0)) }
        case .resume:
            audio.skipUnrecordedSamples()
        case .finish(let done):
            video.finish()
            sound.finish()
            writer.finishWriting {
                if self.writer.status != .completed {
                    PlayLog.session.error("capture-finish-failed \(String(describing: self.writer.error))")
                }
                self.replay.end()
                done()
            }
        }
    }

    /// Real-time inputs refuse samples only while they cannot keep up; a refused sample is retried, never dropped.
    private func flushAppends() throws -> Bool {
        guard !failed else {
            appends.removeAll()
            return true
        }
        while let next = appends.first {
            guard try append(next) else {
                scheduleRetry()
                return false
            }
            appends.removeFirst()
        }
        return true
    }

    private func append(_ next: Append) throws -> Bool {
        switch next {
        case .audio(let buffer):
            return try sound.appendImmediately(buffer)
        case .video(let picture):
            let time = CMTime(value: Int64(picture.clipNs), timescale: CMTimeScale(ClipClock.nanosecondsPerSecond))
            guard try video.appendImmediately(picture.buffer, with: time) else { return false }
            replay.noteFirstFrame(atNs: picture.clipNs)
            return true
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + Self.retryDelay) {
            self.retryScheduled = false
            self.drain()
        }
    }

    private func fail(_ error: any Error) {
        failed = true
        PlayLog.session.error("capture-failed reason=encoder \(error.localizedDescription)")
        writer.cancelWriting()
        replay.end()
    }

    private static func videoSettings(width: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate,
                AVVideoExpectedSourceFrameRateKey: ClipClock.nanosecondsPerSecond / ClipClock.coreFrameNs,
                AVVideoMaxKeyFrameIntervalDurationKey: 1,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
    }

    private static func audioSettings(rate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: audioBitRate,
        ]
    }

    /// The nearest AAC encode rate to the core's, as RetroArch picks it (record_avfoundation.m:73-122).
    private static func encodeRate(nearest rate: Double) -> Double? {
        var format = kAudioFormatMPEG4AAC
        let specifierSize = UInt32(MemoryLayout<AudioFormatID>.size)
        var size: UInt32 = 0
        let property = kAudioFormatProperty_AvailableEncodeSampleRates
        guard AudioFormatGetPropertyInfo(property, specifierSize, &format, &size) == noErr, size > 0 else {
            return nil
        }
        var ranges = [AudioValueRange](
            repeating: AudioValueRange(),
            count: Int(size) / MemoryLayout<AudioValueRange>.size
        )
        guard AudioFormatGetProperty(property, specifierSize, &format, &size, &ranges) == noErr else { return nil }
        return ranges
            .map { min(max(rate, $0.mMinimum), $0.mMaximum) }
            .min { abs($0 - rate) < abs($1 - rate) }
    }
}

extension CVReadOnlyPixelBuffer {
    func renderTexture(device: any MTLDevice) -> (any MTLTexture)? {
        let surface = withUnsafeBuffer { CVPixelBufferGetIOSurface($0).map { $0.takeUnretainedValue() as IOSurface } }
        guard let surface else {
            PlayLog.session.error("capture-surface-missing")
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: surface.width,
            height: surface.height,
            mipmapped: false
        )
        descriptor.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            PlayLog.session.error("capture-texture-failed")
            return nil
        }
        return texture
    }
}
