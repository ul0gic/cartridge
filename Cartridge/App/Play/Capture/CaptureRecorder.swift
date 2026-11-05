import CoreVideo
import Foundation
import Metal
import Observation

@MainActor
@Observable
final class CaptureRecorder: CaptureFrameSink {
    private typealias StillRequest = CheckedContinuation<Result<CVReadOnlyPixelBuffer, CaptureError>, Never>

    private static let replayLengthNs = 30 * ClipClock.nanosecondsPerSecond
    private static let recordingCapNs = 1800 * ClipClock.nanosecondsPerSecond
    private static let skippedLogEvery = 600

    private(set) var isRecording = false
    @ObservationIgnored var onRecordingEnded: ((Result<CaptureItem, CaptureError>) -> Void)?

    @ObservationIgnored private let game: GameRecord
    @ObservationIgnored private let tap: SessionAudioTap?
    @ObservationIgnored private let gallery: any GalleryStoring
    @ObservationIgnored private var stream: SegmentWriter?
    @ObservationIgnored private var streamFailed = false
    @ObservationIgnored private var streamStarting = false
    @ObservationIgnored private var clock = ClipClock()
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var paddedThroughNs: UInt64?
    @ObservationIgnored private var segmentWaits = 0
    @ObservationIgnored private var skippedFrames = 0
    @ObservationIgnored private var recordingFromNs: UInt64?
    @ObservationIgnored private var capTask: Task<Void, Never>?
    @ObservationIgnored private var stillRequests: [StillRequest] = []

    init(game: GameRecord, tap: SessionAudioTap?, gallery: any GalleryStoring) {
        self.game = game
        self.tap = tap
        self.gallery = gallery
    }

    func videoTarget(for frame: PresentedFrame, device: any MTLDevice) -> CaptureTarget? {
        guard !paused, !closed, let stream = stream(for: frame.aspectRatio), !stream.replay.hasEnded,
              let clipNs = clock.time(forDisplay: frame.displayNs)
        else { return nil }
        stopAtCap(clipNs: clipNs, stream: stream)
        guard let target = stream.target(sequence: frame.sequence, clipNs: clipNs, device: device) else {
            skippedFrames += 1
            if skippedFrames == 1 || skippedFrames.isMultiple(of: Self.skippedLogEvery) {
                PlayLog.session.error("capture-frame-skipped count=\(skippedFrames)")
            }
            return nil
        }
        return target
    }

    func stillTarget(device: any MTLDevice, aspectRatio: Double) -> CaptureTarget? {
        guard !stillRequests.isEmpty else { return nil }
        let request = stillRequests.removeFirst()
        let width = Self.evenWidth(height: StillWriter.pixelHeight, aspectRatio: aspectRatio)
        guard let buffer = StillWriter.makeBuffer(width: width),
              let texture = buffer.renderTexture(device: device)
        else {
            request.resume(returning: .failure(.encoderFailed))
            return nil
        }
        return CaptureTarget(texture: texture) { rendered in
            request.resume(returning: rendered ? .success(buffer) : .failure(.encoderFailed))
        }
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        if paused {
            if segmentWaits > 0 {
                padOpenSegment()
            }
        } else {
            clock.resume()
            stream?.resume()
        }
    }

    func screenshot() async throws(CaptureError) -> CaptureItem {
        let began = ContinuousClock.now
        let capturedAt = Date.now
        do throws(CaptureError) {
            guard !closed else { throw .nothingCaptured }
            let buffer = try await withCheckedContinuation { stillRequests.append($0) }.get()
            let url = gallery.newFileURL(kind: .screenshot, gameTitle: game.title, capturedAt: capturedAt)
            try await StillWriter.write(buffer, to: url)
            let item = CaptureItem(
                id: UUID(),
                kind: .screenshot,
                fileName: url.lastPathComponent,
                gameID: game.id,
                gameTitle: game.title,
                capturedAt: capturedAt,
                pixelWidth: buffer.withUnsafeBuffer { CVPixelBufferGetWidth($0) },
                pixelHeight: StillWriter.pixelHeight,
                durationSeconds: nil
            )
            try add(item, at: url)
            let milliseconds = PlaySession.milliseconds(since: began)
            PlayLog.session.info("capture-screenshot ms=\(milliseconds) height=\(StillWriter.pixelHeight)")
            return item
        } catch {
            throw Self.logged(error, "screenshot")
        }
    }

    func startRecording() throws(CaptureError) {
        do throws(CaptureError) {
            guard !isRecording, !closed, let stream, let fromNs = clock.lastFrameNs else { throw .nothingCaptured }
            let url = try CaptureFiles.newPartialURL(pathExtension: CaptureKind.clip.fileExtension)
            guard stream.replay.startRecording(to: url, fromNs: fromNs) else { throw .encoderFailed }
            recordingFromNs = fromNs
            isRecording = true
            PlayLog.session.info("recording-started")
        } catch {
            throw Self.logged(error, "recording")
        }
    }

    func stopRecording() async throws(CaptureError) -> CaptureItem {
        guard isRecording, let stream, let lastNs = clock.lastFrameNs, let stopNs = clock.contentEndNs else {
            throw Self.logged(.nothingCaptured, "recording")
        }
        _ = await closeSegment(covering: lastNs, of: stream)
        return try await finishRecording(covering: lastNs, trimAt: stopNs, reason: "user", of: stream).get()
    }

    func saveReplay() async throws(CaptureError) -> CaptureItem {
        let began = ContinuousClock.now
        do throws(CaptureError) {
            guard let stream, let lastNs = clock.lastFrameNs, let endNs = clock.contentEndNs else {
                throw .nothingCaptured
            }
            guard await closeSegment(covering: lastNs, of: stream) else { throw .encoderFailed }
            guard let snapshot = stream.replay.snapshot(endingAt: endNs, lengthNs: Self.replayLengthNs) else {
                throw .nothingCaptured
            }
            let fragment = try await ClipExporter.writeFragment(snapshot)
            let clip = try await exportClip(fragment, startNs: snapshot.startNs, endNs: endNs, width: stream.width)
            let milliseconds = PlaySession.milliseconds(since: began)
            PlayLog.session.info("replay-saved ms=\(milliseconds) duration-s=\(String(format: "%.1f", clip.seconds))")
            return clip.item
        } catch {
            throw Self.logged(error, "replay")
        }
    }

    func close() async {
        guard !closed else { return }
        closed = true
        for request in stillRequests {
            request.resume(returning: .failure(.nothingCaptured))
        }
        stillRequests.removeAll()
        if capTask != nil {
            padOpenSegment()
        }
        await capTask?.value
        guard let stream else { return }
        self.stream = nil
        if isRecording, let lastNs = clock.lastFrameNs, let stopNs = clock.contentEndNs {
            await stream.finish(contentEndNs: stopNs)
            _ = await finishRecording(covering: lastNs, trimAt: stopNs, reason: "quit", of: stream)
        } else {
            stream.cancel()
        }
    }

    private func stream(for aspectRatio: Double) -> SegmentWriter? {
        if let stream {
            return stream
        }
        guard !streamFailed, !streamStarting else { return nil }
        streamStarting = true
        let width = Self.evenWidth(height: SegmentWriter.pixelHeight, aspectRatio: aspectRatio)
        Task { [tap] in
            let made = await Self.makeStream(width: width, tap: tap)
            streamStarting = false
            switch made {
            case .success(let stream) where closed:
                stream.cancel()
            case .success(let stream):
                self.stream = stream
            case .failure(let error):
                streamFailed = true
                PlayLog.session.error("capture-failed reason=stream-\(error)")
            }
        }
        return nil
    }

    @concurrent
    private static func makeStream(width: Int, tap: SessionAudioTap?) async -> Result<SegmentWriter, CaptureError> {
        do throws(CaptureError) {
            return try .success(SegmentWriter(width: width, tap: tap))
        } catch {
            return .failure(error)
        }
    }

    private func stopAtCap(clipNs: UInt64, stream: SegmentWriter) {
        guard isRecording, capTask == nil, let fromNs = recordingFromNs else { return }
        let stopNs = (stream.replay.recordingStartNs ?? fromNs) + Self.recordingCapNs
        guard clipNs >= stopNs else { return }
        capTask = Task {
            _ = await closeSegment(covering: stopNs - 1, of: stream)
            let result = await finishRecording(covering: stopNs - 1, trimAt: stopNs, reason: "cap", of: stream)
            capTask = nil
            onRecordingEnded?(result)
        }
    }

    private func closeSegment(covering instantNs: UInt64, of stream: SegmentWriter) async -> Bool {
        segmentWaits += 1
        defer { segmentWaits -= 1 }
        if paused, !stream.replay.covers(instantNs) {
            padOpenSegment()
        }
        return await stream.replay.waitForSegment(covering: instantNs)
    }

    private func padOpenSegment() {
        guard let stream, let contentEndNs = clock.contentEndNs, paddedThroughNs != contentEndNs else { return }
        paddedThroughNs = contentEndNs
        stream.pad(times: clock.padTimes(), contentEndNs: contentEndNs)
    }

    private func finishRecording(
        covering instantNs: UInt64,
        trimAt stopNs: UInt64,
        reason: String,
        of stream: SegmentWriter
    ) async -> Result<CaptureItem, CaptureError> {
        isRecording = false
        recordingFromNs = nil
        do throws(CaptureError) {
            let clip = try await stream.replay.stopRecording(covering: instantNs).get()
            let endNs = min(stopNs, clip.endNs)
            guard endNs > clip.startNs else {
                CaptureFiles.remove(clip.url)
                throw .nothingCaptured
            }
            let saved = try await exportClip(clip.url, startNs: clip.startNs, endNs: endNs, width: stream.width)
            let seconds = String(format: "%.1f", saved.seconds)
            PlayLog.session.info("recording-stopped reason=\(reason) duration-s=\(seconds)")
            return .success(saved.item)
        } catch {
            return .failure(Self.logged(error, "recording"))
        }
    }

    private func exportClip(
        _ fragment: URL,
        startNs: UInt64,
        endNs: UInt64,
        width: Int
    ) async throws(CaptureError) -> (item: CaptureItem, seconds: Double) {
        let capturedAt = Date.now
        let url = gallery.newFileURL(kind: .clip, gameTitle: game.title, capturedAt: capturedAt)
        let duration = try await ClipExporter.remux(fragment, lengthNs: endNs - startNs, to: url)
        let item = CaptureItem(
            id: UUID(),
            kind: .clip,
            fileName: url.lastPathComponent,
            gameID: game.id,
            gameTitle: game.title,
            capturedAt: capturedAt,
            pixelWidth: width,
            pixelHeight: SegmentWriter.pixelHeight,
            durationSeconds: duration
        )
        try add(item, at: url)
        return (item, duration)
    }

    private func add(_ item: CaptureItem, at url: URL) throws(CaptureError) {
        do {
            try gallery.add(item)
        } catch {
            CaptureFiles.remove(url)
            throw CaptureError(gallery: error)
        }
    }

    private static func evenWidth(height: Int, aspectRatio: Double) -> Int {
        max(2, Int((Double(height) * aspectRatio / 2).rounded()) * 2)
    }

    private static func logged(_ error: CaptureError, _ action: String) -> CaptureError {
        PlayLog.session.error("capture-failed reason=\(action)-\(error)")
        return error
    }
}
