import Foundation
import System

private struct SnapshotMarker: Codable {
    static let currentVersion = 1
    static let tagPrefix = "c-"
    static let tagLength = 38
    static let maxBytes = 4096

    let version: Int
    let tag: String
    let savedAt: String

    static func newTag() -> String {
        tagPrefix + UUID().uuidString.lowercased()
    }

    static func readTag(atPath path: String) throws(XboxHostFailure) -> String {
        let data: Data?
        do {
            data = try FileHandle(forReadingFrom: URL(filePath: path)).read(upToCount: maxBytes + 1)
        } catch {
            throw XboxHostFailure(code: .unserializeFailed, message: "snapshot marker: \(error.localizedDescription)")
        }
        guard let data, data.count <= maxBytes else {
            throw XboxHostFailure(code: .unserializeFailed, message: "snapshot marker is empty or too large")
        }
        let marker: SnapshotMarker
        do {
            marker = try JSONDecoder().decode(SnapshotMarker.self, from: data)
        } catch {
            throw XboxHostFailure(code: .unserializeFailed, message: "snapshot marker: \(error.localizedDescription)")
        }
        guard marker.version == currentVersion, isValidTag(marker.tag) else {
            throw XboxHostFailure(code: .unserializeFailed, message: "snapshot marker version or tag is not supported")
        }
        return marker.tag
    }

    static func write(tag: String, toPath path: String) throws(XboxHostFailure) {
        let temporary = path + ".tmp"
        do {
            let marker = SnapshotMarker(version: currentVersion, tag: tag, savedAt: Date().ISO8601Format())
            let data = try JSONEncoder().encode(marker)
            let descriptor = try FileDescriptor.open(
                FilePath(temporary),
                .writeOnly,
                options: [.create, .truncate, .closeOnExec],
                permissions: .ownerReadWrite
            )
            try descriptor.closeAfter {
                _ = try descriptor.writeAll(data)
                guard fsync(descriptor.rawValue) == 0 else { throw Errno(rawValue: errno) }
            }
            guard rename(temporary, path) == 0 else { throw Errno(rawValue: errno) }
        } catch {
            unlink(temporary)
            let full = (error as? Errno).map { $0 == .noSpace || $0 == .diskQuotaExceeded } == true
            throw XboxHostFailure(code: full ? .diskFull : .writeFailed, message: "snapshot marker: \(error)")
        }
    }

    private static func isValidTag(_ tag: String) -> Bool {
        tag.count == tagLength && tag.hasPrefix(tagPrefix)
            && tag.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }
}

private final class TagCollector {
    var tags: [String] = []
}

extension XboxSession {
    private static let restoreTimeout = DispatchTimeInterval.seconds(5)

    func saveState(toPath path: String) throws(XboxHostFailure) {
        let began = Self.nowNs()
        let tag = SnapshotMarker.newTag()
        let status = tag.withCString(library.saveSnapshot)
        guard status == CARTRIDGE_XEMU_OK else {
            throw XboxHostFailure(
                code: Self.saveFailureCode(status),
                call: "cartridge_xemu_save_snapshot",
                status: status
            )
        }
        do throws(XboxHostFailure) {
            try SnapshotMarker.write(tag: tag, toPath: path)
        } catch {
            deleteSnapshot(tag)
            throw error
        }
        XboxHostLog.session
            .notice("xbox-snapshot-saved ms=\(Self.milliseconds(since: began)) drive-bytes=\(driveBytes)")
    }

    func loadState(fromPath path: String) throws(XboxHostFailure) {
        let began = Self.nowNs()
        let restoring = awaitingRestore
        awaitingRestore = false
        let tag: String
        do throws(XboxHostFailure) {
            tag = try SnapshotMarker.readTag(atPath: path)
        } catch {
            if restoring {
                resetAfterFailedLoad()
            }
            throw error
        }
        let status = tag.withCString(library.loadSnapshot)
        guard status == CARTRIDGE_XEMU_OK else {
            if restoring || status == CARTRIDGE_XEMU_SNAPSHOT_FAILED {
                resetAfterFailedLoad()
            }
            let code: CoreHostErrorCode = status == CARTRIDGE_XEMU_NOT_STARTED ? .notStarted : .unserializeFailed
            throw XboxHostFailure(code: code, call: "cartridge_xemu_load_snapshot", status: status)
        }
        if paused {
            setRunning(false)
        }
        XboxHostLog.session.notice("xbox-snapshot-loaded ms=\(Self.milliseconds(since: began))")
    }

    private func resetAfterFailedLoad() {
        reset()
        if !paused {
            setRunning(true)
        }
        XboxHostLog.session.notice("xbox-snapshot-load-reset")
    }

    func scheduleRestoreTimeout(on queue: DispatchQueue) {
        guard awaitingRestore else { return }
        queue.asyncAfter(deadline: .now() + Self.restoreTimeout) { [self] in
            guard awaitingRestore else { return }
            awaitingRestore = false
            XboxHostLog.session.notice("xbox-restore-timeout")
            if !paused {
                setRunning(true)
            }
        }
    }

    func collectSnapshotGarbage() {
        guard let tags = snapshotTags(), let referenced = referencedTags() else { return }
        var deleted = 0
        for tag in tags where !referenced.contains(tag) && deleteSnapshot(tag) {
            deleted += 1
        }
        XboxHostLog.session.notice("xbox-gc deleted=\(deleted)")
    }

    @discardableResult
    private func deleteSnapshot(_ tag: String) -> Bool {
        let status = tag.withCString(library.deleteSnapshot)
        guard status == CARTRIDGE_XEMU_OK else {
            XboxHostLog.session.error("cartridge_xemu_delete_snapshot returned status \(status.rawValue) tag=\(tag)")
            return false
        }
        return true
    }

    private func snapshotTags() -> [String]? {
        let collector = TagCollector()
        let status = withExtendedLifetime(collector) {
            library.listSnapshots({ context, tag in
                guard let context, let tag else { return }
                Unmanaged<TagCollector>.fromOpaque(context).takeUnretainedValue().tags.append(String(cString: tag))
            }, Unmanaged.passUnretained(collector).toOpaque())
        }
        guard status == CARTRIDGE_XEMU_OK else {
            XboxHostLog.session
                .error("xbox-gc-skipped cartridge_xemu_list_snapshots returned status \(status.rawValue)")
            return nil
        }
        return collector.tags
    }

    private func referencedTags() -> Set<String>? {
        var markers = [saveDirectory.appending(path: "state-resume.state", directoryHint: .notDirectory)]
        let slots = saveDirectory.appending(path: "slots", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: slots.path) {
            do {
                markers += try FileManager.default.contentsOfDirectory(at: slots, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "state" }
            } catch {
                XboxHostLog.session.error("xbox-gc-skipped slots: \(error.localizedDescription)")
                return nil
            }
        }
        var tags: Set<String> = []
        for marker in markers where FileManager.default.fileExists(atPath: marker.path) {
            do throws(XboxHostFailure) {
                try tags.insert(SnapshotMarker.readTag(atPath: marker.path))
            } catch {
                XboxHostLog.session.error("xbox-gc-skipped \(marker.lastPathComponent): \(error.message)")
                return nil
            }
        }
        return tags
    }

    private var driveBytes: String {
        var info = stat()
        guard stat(gameDrivePath, &info) == 0 else { return "unknown" }
        return String(info.st_size)
    }

    private static func saveFailureCode(_ status: CartridgeXemuStatus) -> CoreHostErrorCode {
        switch status {
        case CARTRIDGE_XEMU_DISK_FULL: .diskFull
        case CARTRIDGE_XEMU_NOT_STARTED: .notStarted
        default: .serializeFailed
        }
    }
}
