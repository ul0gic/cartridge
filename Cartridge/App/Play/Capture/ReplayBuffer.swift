import AVFoundation
import Synchronization

struct ClipSnapshot: Sendable {
    let initialization: Data
    let segments: [ClipSegment]

    var startNs: UInt64 {
        segments.first?.startNs ?? 0
    }
}

final class ReplayBuffer: NSObject, AVAssetWriterDelegate, Sendable {
    static let keptNs = 31 * ClipClock.nanosecondsPerSecond

    private struct Waiter {
        let instantNs: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct Stop {
        let instantNs: UInt64
        let continuation: CheckedContinuation<Result<RecordingClip, CaptureError>, Never>
    }

    private struct State {
        var initialization: Data?
        var segments: [ClipSegment] = []
        var keptNs: UInt64 = 0
        var firstFrameNs: UInt64?
        var originNs: Int64?
        var newestEndNs: UInt64?
        var recording: RecordingFile?
        var stop: Stop?
        var waiters: [Waiter] = []
        var ended = false

        mutating func add(_ segment: ClipSegment) {
            segments.append(segment)
            keptNs += segment.durationNs
            while let oldest = segments.first, keptNs - oldest.durationNs >= ReplayBuffer.keptNs {
                segments.removeFirst()
                keptNs -= oldest.durationNs
            }
            newestEndNs = segment.endNs
            if let initialization {
                recording?.append(segment, initialization: initialization)
            }
            waiters.removeAll { waiter in
                guard segment.endNs > waiter.instantNs else { return false }
                waiter.continuation.resume(returning: true)
                return true
            }
            if let stop, segment.endNs > stop.instantNs {
                self.stop = nil
                stop.continuation.resume(returning: finishRecording())
            }
        }

        mutating func finishRecording() -> Result<RecordingClip, CaptureError> {
            guard var recording else { return .failure(.nothingCaptured) }
            self.recording = nil
            return recording.finish()
        }
    }

    private let state = Mutex(State())

    var hasEnded: Bool {
        state.withLock { $0.ended }
    }

    var recordingStartNs: UInt64? {
        state.withLock { $0.recording?.startNs }
    }

    func assetWriter(
        _: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        guard segmentType == .separable else {
            state.withLock { $0.initialization = segmentData }
            return
        }
        guard let video = segmentReport?.trackReports.first(where: { $0.mediaType == .video }) else {
            PlayLog.session.error("capture-segment-unreported bytes=\(segmentData.count)")
            return
        }
        // `finishWriting` emits a last segment with a zero-length video report and no frames (Spike 0C, replay.md).
        guard video.duration > .zero else { return }
        let reportNs = Self.nanoseconds(video.earliestPresentationTimeStamp)
        let durationNs = UInt64(clamping: Self.nanoseconds(video.duration))
        state.withLock { state in
            guard let firstFrameNs = state.firstFrameNs else {
                PlayLog.session.error("capture-segment-before-frame bytes=\(segmentData.count)")
                return
            }
            // Video reports run 48.33 ms ahead of the appended times (Spike 0C, replay.md); segment 0 holds the first.
            let originNs = state.originNs ?? reportNs - Int64(firstFrameNs)
            state.originNs = originNs
            let startNs = UInt64(clamping: reportNs - originNs)
            state.add(ClipSegment(startNs: startNs, durationNs: durationNs, data: segmentData))
        }
    }

    func noteFirstFrame(atNs clipNs: UInt64) {
        state.withLock { $0.firstFrameNs = $0.firstFrameNs ?? clipNs }
    }

    func covers(_ instantNs: UInt64) -> Bool {
        state.withLock { state in state.newestEndNs.map { $0 > instantNs } ?? false }
    }

    func waitForSegment(covering instantNs: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                if let newest = state.newestEndNs, newest > instantNs {
                    continuation.resume(returning: true)
                } else if state.ended {
                    continuation.resume(returning: false)
                } else {
                    state.waiters.append(Waiter(instantNs: instantNs, continuation: continuation))
                }
            }
        }
    }

    func snapshot(endingAt endNs: UInt64, lengthNs: UInt64) -> ClipSnapshot? {
        state.withLock { state in
            guard let initialization = state.initialization else { return nil }
            let fromNs = endNs > lengthNs ? endNs - lengthNs : 0
            let segments = state.segments.filter { $0.endNs > fromNs && $0.startNs < endNs }
            return segments.isEmpty ? nil : ClipSnapshot(initialization: initialization, segments: segments)
        }
    }

    func startRecording(to url: URL, fromNs: UInt64) -> Bool {
        state.withLock { state in
            guard state.recording == nil, !state.ended else { return false }
            state.recording = RecordingFile(url: url, fromNs: fromNs)
            return true
        }
    }

    func stopRecording(covering instantNs: UInt64) async -> Result<RecordingClip, CaptureError> {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                let reached = state.recording?.endNs.map { $0 > instantNs } ?? false
                if state.ended || state.recording == nil || reached {
                    continuation.resume(returning: state.finishRecording())
                } else {
                    state.stop = Stop(instantNs: instantNs, continuation: continuation)
                }
            }
        }
    }

    func end() {
        state.withLock { state in
            state.ended = true
            for waiter in state.waiters {
                waiter.continuation.resume(returning: false)
            }
            state.waiters.removeAll()
            if let stop = state.stop {
                state.stop = nil
                stop.continuation.resume(returning: state.finishRecording())
            }
        }
    }

    private static func nanoseconds(_ time: CMTime) -> Int64 {
        time.convertScale(Int32(ClipClock.nanosecondsPerSecond), method: .roundHalfAwayFromZero).value
    }
}
