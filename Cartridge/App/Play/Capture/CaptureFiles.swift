import Foundation

enum CaptureFiles {
    static func newPartialURL(pathExtension: String) throws(CaptureError) -> URL {
        do {
            try FileManager.default.createDirectory(at: StoragePaths.galleryPartial, withIntermediateDirectories: true)
        } catch {
            PlayLog.session.error("capture-partial-folder-failed \(error.localizedDescription)")
            throw CaptureError(writing: error)
        }
        return StoragePaths.galleryPartial
            .appending(path: "\(UUID().uuidString).\(pathExtension)", directoryHint: .notDirectory)
    }

    static func move(_ source: URL, to destination: URL) throws(CaptureError) {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            PlayLog.session.error("capture-move-failed \(error.localizedDescription)")
            throw CaptureError(writing: error)
        }
    }

    static func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            PlayLog.session.error("capture-remove-failed \(error.localizedDescription)")
        }
    }
}

extension CaptureError {
    init(writing error: any Error) {
        let isDiskFull = (error as? CocoaError)?.code == .fileWriteOutOfSpace
            || (error as? POSIXError)?.code == .ENOSPC
        self = isDiskFull ? .diskFull : .writeFailed
    }

    init(gallery error: GalleryError) {
        self = error == .diskFull ? .diskFull : .writeFailed
    }
}
