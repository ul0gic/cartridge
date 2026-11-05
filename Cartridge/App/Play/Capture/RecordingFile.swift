import Foundation

struct ClipSegment: Sendable {
    let startNs: UInt64
    let durationNs: UInt64
    let data: Data

    var endNs: UInt64 {
        startNs + durationNs
    }
}

struct RecordingClip: Sendable {
    let url: URL
    let startNs: UInt64
    let endNs: UInt64
}

struct RecordingFile {
    private let url: URL
    private let fromNs: UInt64
    private var handle: FileHandle?
    private var failure: CaptureError?
    private(set) var startNs: UInt64?
    private(set) var endNs: UInt64?

    init(url: URL, fromNs: UInt64) {
        self.url = url
        self.fromNs = fromNs
    }

    mutating func append(_ segment: ClipSegment, initialization: Data) {
        guard failure == nil, segment.endNs > fromNs else { return }
        do {
            if handle == nil {
                handle = try open(writing: initialization)
            }
            try handle?.write(contentsOf: segment.data)
            startNs = startNs ?? segment.startNs
            endNs = segment.endNs
        } catch {
            PlayLog.session.error("recording-append-failed \(error.localizedDescription)")
            failure = CaptureError(writing: error)
            close()
            CaptureFiles.remove(url)
        }
    }

    mutating func finish() -> Result<RecordingClip, CaptureError> {
        close()
        if let failure {
            return .failure(failure)
        }
        guard let startNs, let endNs else {
            CaptureFiles.remove(url)
            return .failure(.nothingCaptured)
        }
        return .success(RecordingClip(url: url, startNs: startNs, endNs: endNs))
    }

    private func open(writing initialization: Data) throws -> FileHandle {
        try initialization.write(to: url)
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        return opened
    }

    private mutating func close() {
        guard let handle else { return }
        self.handle = nil
        do {
            try handle.close()
        } catch {
            PlayLog.session.error("recording-close-failed \(error.localizedDescription)")
            failure = failure ?? CaptureError(writing: error)
        }
    }
}
