import AVFoundation

enum ClipExporter {
    @concurrent
    static func writeFragment(_ snapshot: ClipSnapshot) async throws(CaptureError) -> URL {
        let fragment = try CaptureFiles.newPartialURL(pathExtension: CaptureKind.clip.fileExtension)
        var data = snapshot.initialization
        for segment in snapshot.segments {
            data.append(segment.data)
        }
        do {
            try data.write(to: fragment)
        } catch {
            PlayLog.session.error("replay-fragment-failed \(error.localizedDescription)")
            CaptureFiles.remove(fragment)
            throw CaptureError(writing: error)
        }
        return fragment
    }

    @concurrent
    static func remux(_ fragment: URL, lengthNs: UInt64, to destination: URL) async throws(CaptureError) -> Double {
        defer { CaptureFiles.remove(fragment) }
        let asset = AVURLAsset(url: fragment)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            PlayLog.session.error("capture-export-unavailable")
            throw .encoderFailed
        }
        let length = CMTime(value: Int64(lengthNs), timescale: CMTimeScale(ClipClock.nanosecondsPerSecond))
        session.timeRange = CMTimeRange(start: .zero, duration: length)
        do {
            try await session.export(to: destination, as: .mp4)
            return try await AVURLAsset(url: destination).load(.duration).seconds
        } catch {
            PlayLog.session.error("capture-export-failed \(error.localizedDescription)")
            CaptureFiles.remove(destination)
            throw (error as? AVError)?.code == .diskFull ? .diskFull : CaptureError(writing: error)
        }
    }
}
