import Foundation

@MainActor
final class SaveBackupStore {
    private static let filePrefix = "battery-"
    private static let fileExtension = "srm"
    private static let stampLength = "yyyy-MM-dd-HHmmss".count

    private let fileManager = FileManager.default
    private let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    func backups(for id: GameID) -> [SaveBackup] {
        let folder = StoragePaths.backupsFolder(for: id)
        guard fileManager.fileExists(atPath: folder.path) else { return [] }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
        } catch {
            LibraryLog.logger.error("backups-unreadable game=\(id.rawValue) error=\(error.localizedDescription)")
            return []
        }
        return urls
            .compactMap(parse)
            .sorted { ($0.backup.createdAt, $0.sequence) > ($1.backup.createdAt, $1.sequence) }
            .map(\.backup)
    }

    func backUp(_ id: GameID) throws(SaveFileError) -> SaveBackup {
        let source = StoragePaths.batterySave(for: id)
        guard fileManager.fileExists(atPath: source.path) else { throw .noBatterySave }
        let data = try readRegularFile(at: source, expectedBytes: nil)
        return try writeBackup(data, for: id)
    }

    func restore(_ backup: SaveBackup, for id: GameID) throws(SaveFileError) -> SaveBackup? {
        let data = try readRegularFile(at: backup.url, expectedBytes: nil)
        let previous = try backUpIfPresent(id)
        try replaceBatterySave(with: data, for: id)
        LibraryLog.logger.info("save-restored bytes=\(data.count)")
        return previous
    }

    func importSave(from url: URL, for id: GameID, expectedBytes: Int) throws(SaveFileError) -> SaveBackup? {
        let data: Data
        do {
            data = try readRegularFile(at: url, expectedBytes: expectedBytes)
        } catch {
            LibraryLog.logger.info("save-import-refused reason=\(Self.refusalReason(error))")
            throw error
        }
        let previous = try backUpIfPresent(id)
        try replaceBatterySave(with: data, for: id)
        LibraryLog.logger.info("save-imported bytes=\(data.count)")
        return previous
    }

    private func backUpIfPresent(_ id: GameID) throws(SaveFileError) -> SaveBackup? {
        guard fileManager.fileExists(atPath: StoragePaths.batterySave(for: id).path) else { return nil }
        return try backUp(id)
    }

    private static func backupURL(in folder: URL, stamp: String, sequence: Int) -> URL {
        let suffix = sequence == 1 ? "" : "-\(sequence)"
        return folder.appending(path: "\(filePrefix)\(stamp)\(suffix).\(fileExtension)", directoryHint: .notDirectory)
    }

    private static func refusalReason(_ error: SaveFileError) -> String {
        switch error {
        case .notARegularFile: "not-regular-file"
        case .wrongSize: "wrong-size"
        case .noBatterySave, .unreadable, .writeFailed, .diskFull: "unreadable"
        }
    }

    private func parse(_ url: URL) -> (backup: SaveBackup, sequence: Int)? {
        let name = url.deletingPathExtension().lastPathComponent
        guard url.pathExtension == Self.fileExtension, name.hasPrefix(Self.filePrefix) else { return nil }
        let rest = name.dropFirst(Self.filePrefix.count)
        let suffix = rest.dropFirst(Self.stampLength)
        let sequence: Int
        if suffix.isEmpty {
            sequence = 1
        } else if suffix.hasPrefix("-"), let number = Int(suffix.dropFirst()), number >= 2 {
            sequence = number
        } else {
            return nil
        }
        guard let createdAt = stampFormatter.date(from: String(rest.prefix(Self.stampLength))),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let bytes = values.fileSize
        else { return nil }
        return (SaveBackup(url: url, createdAt: createdAt, bytes: bytes), sequence)
    }

    private func readRegularFile(at url: URL, expectedBytes: Int?) throws(SaveFileError) -> Data {
        let resolved = url.resolvingSymlinksInPath()
        let values: URLResourceValues
        do {
            values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw .unreadable
        }
        guard values.isRegularFile == true, let size = values.fileSize else { throw .notARegularFile }
        if let expectedBytes, size != expectedBytes {
            throw .wrongSize(expected: expectedBytes, actual: size)
        }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: resolved)
            data = try handle.read(upToCount: size + 1) ?? Data()
            try handle.close()
        } catch {
            throw .unreadable
        }
        if let expectedBytes, data.count != expectedBytes {
            throw .wrongSize(expected: expectedBytes, actual: data.count)
        }
        return data
    }

    private func writeBackup(_ data: Data, for id: GameID) throws(SaveFileError) -> SaveBackup {
        let folder = StoragePaths.backupsFolder(for: id)
        let createdAt = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        let stamp = stampFormatter.string(from: createdAt)
        var destination = Self.backupURL(in: folder, stamp: stamp, sequence: 1)
        var sequence = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = Self.backupURL(in: folder, stamp: stamp, sequence: sequence)
            sequence += 1
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch {
            LibraryLog.logger.error("backup-failed game=\(id.rawValue)")
            throw HubFiles.saveFileError(from: error)
        }
        LibraryLog.logger.info("backup-written bytes=\(data.count)")
        return SaveBackup(url: destination, createdAt: createdAt, bytes: data.count)
    }

    private func replaceBatterySave(with data: Data, for id: GameID) throws(SaveFileError) {
        do {
            try data.write(to: StoragePaths.batterySave(for: id), options: .atomic)
        } catch {
            LibraryLog.logger.error("battery-replace-failed game=\(id.rawValue)")
            throw HubFiles.saveFileError(from: error)
        }
    }
}
