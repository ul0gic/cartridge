import AVFoundation

struct ClipAudio {
    typealias Buffer = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>

    /// RetroArch's encoder rate when the core's is unknown (record_avfoundation.m:100).
    private static let silentRate = 44100
    private static let bytesPerFrame = 4

    let sampleRate: Int
    private let tap: SessionAudioTap?
    private let format: CMAudioFormatDescription
    private let toleranceSamples: Int64
    private var tagCursor: UInt64?
    private var readPosition: UInt64?
    private var clipPosition: Int64 = 0
    private var skipUnrecorded = true

    init(tap: SessionAudioTap?) throws {
        let tapRate = Int(tap?.sampleRate ?? 0)
        if tapRate == 0 {
            PlayLog.session.error("tap-unavailable")
        }
        sampleRate = tapRate > 0 ? tapRate : Self.silentRate
        self.tap = tapRate > 0 ? tap : nil
        let description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(Self.bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(Self.bytesPerFrame),
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        format = try CMAudioFormatDescription(audioStreamBasicDescription: description)
        toleranceSamples = Self.samples(atNs: ClipClock.coreFrameNs, rate: sampleRate)
    }

    mutating func skipUnrecordedSamples() {
        skipUnrecorded = true
    }

    mutating func buffers(before sequence: UInt64, startingAt clipNs: UInt64) -> [Buffer] {
        let tapEnd = sequence > 0 ? sampleEnd(through: sequence - 1) : nil
        return buffers(tapEnd: tapEnd, anchor: Self.samples(atNs: clipNs, rate: sampleRate))
    }

    mutating func buffers(through sequence: UInt64, endingAt clipNs: UInt64) -> [Buffer] {
        buffers(tapEnd: sampleEnd(through: sequence), anchor: Self.samples(atNs: clipNs, rate: sampleRate))
    }

    mutating func silence(until clipNs: UInt64) -> [Buffer] {
        silence(until: Self.samples(atNs: clipNs, rate: sampleRate))
    }

    private mutating func silence(until anchor: Int64) -> [Buffer] {
        let missing = anchor - clipPosition
        return missing > 0 ? [silenceBuffer(count: Int(missing))] : []
    }

    private mutating func buffers(tapEnd: UInt64?, anchor: Int64) -> [Buffer] {
        guard let start = readPosition, !skipUnrecorded else {
            readPosition = tapEnd ?? readPosition
            skipUnrecorded = false
            return silence(until: anchor)
        }
        let end = max(tapEnd ?? start, start)
        readPosition = end
        var from = start
        var count = Int64(end - start)
        let excess = clipPosition + count - anchor
        if excess > toleranceSamples {
            let dropped = min(excess, count)
            from += UInt64(dropped)
            count -= dropped
        }
        let oldest = oldestReadableSample()
        if from < oldest, count > 0 {
            let lost = min(Int64(oldest - from), count)
            PlayLog.session.error("tap-lapped frames=\(lost)")
            from += UInt64(lost)
            count -= lost
        }
        var buffers: [Buffer] = []
        let shortfall = anchor - (clipPosition + count)
        if shortfall > toleranceSamples {
            buffers.append(silenceBuffer(count: Int(shortfall)))
        }
        if count > 0 {
            buffers.append(tapBuffer(from: from, count: Int(count)))
        }
        return buffers
    }

    private mutating func sampleEnd(through sequence: UInt64) -> UInt64? {
        guard let tap else { return nil }
        var cursor = tagCursor ?? Self.oldestTag(of: tap)
        var end: UInt64?
        while cursor < tap.tagsWritten {
            guard let tag = tap.tag(at: cursor) else {
                cursor = max(cursor + 1, Self.oldestTag(of: tap))
                continue
            }
            guard tag.frameSequence <= sequence else { break }
            end = tag.sampleEnd
            cursor += 1
        }
        tagCursor = cursor
        return end
    }

    private func oldestReadableSample() -> UInt64 {
        guard let tap else { return 0 }
        let written = tap.samplesWritten
        let span = UInt64(CARTRIDGE_TAP_FRAMES) - UInt64(CARTRIDGE_TAP_WRITE_CHUNK)
        return written > span ? written - span : 0
    }

    private mutating func tapBuffer(from frame: UInt64, count: Int) -> Buffer {
        var block = CMMutableDataBlockBuffer(count: count * Self.bytesPerFrame)
        let copied = block.withContiguousMutableStorageIfAvailable { bytes in
            guard let tap, let samples = bytes.bindMemory(to: Int16.self).baseAddress else { return false }
            return tap.copySamples(from: frame, count: count, into: samples)
        }
        if copied != true {
            PlayLog.session.error("tap-lapped frames=\(count)")
            block.replaceAll(repeating: 0)
        }
        return sampleBuffer(block, count: count)
    }

    private mutating func silenceBuffer(count: Int) -> Buffer {
        var block = CMMutableDataBlockBuffer(count: count * Self.bytesPerFrame)
        block.replaceAll(repeating: 0)
        return sampleBuffer(block, count: count)
    }

    private mutating func sampleBuffer(_ block: consuming CMMutableDataBlockBuffer, count: Int) -> Buffer {
        let ready = CMReadySampleBuffer(
            audioDataBuffer: CMReadOnlyDataBlockBuffer(block),
            formatDescription: format,
            sampleCount: count,
            presentationTimeStamp: CMTime(value: clipPosition, timescale: CMTimeScale(sampleRate))
        )
        clipPosition += Int64(count)
        return Buffer(ready)
    }

    private static func oldestTag(of tap: SessionAudioTap) -> UInt64 {
        let written = tap.tagsWritten
        let kept = UInt64(CARTRIDGE_TAP_TAGS) - 1
        return written > kept ? written - kept : 0
    }

    private static func samples(atNs ns: UInt64, rate: Int) -> Int64 {
        Int64((Double(ns) * Double(rate) / Double(ClipClock.nanosecondsPerSecond)).rounded())
    }
}
