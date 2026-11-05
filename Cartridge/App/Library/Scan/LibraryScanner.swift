import Foundation

enum ScanEvent: Sendable {
    case filesFound(Int)
    case fileChecked
    case gameFound(GameRecord)
    case finished
}

actor LibraryScanner {
    private struct FileEntry {
        let url: URL
        let size: Int64
        let modified: Date
    }

    private static let systemsByExtension: [String: GameSystem] = {
        var map: [String: GameSystem] = [:]
        for system in GameSystem.allCases {
            for fileExtension in system.fileExtensions {
                map[fileExtension] = system
            }
        }
        return map
    }()

    private static let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

    private let database: GameDatabase

    init(databaseDirectory: URL? = nil) {
        database = GameDatabase(directory: databaseDirectory)
    }

    func validate(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            throw LibraryError.folderMissing(path: folder.path)
        }
        guard isDirectory.boolValue else { throw LibraryError.notAFolder(path: folder.path) }
    }

    func hasChanged(folder: URL, fileCount: Int, since: Date) throws -> Bool {
        let files = try listFiles(in: Self.canonical(folder))
        return files.count != fileCount || files.contains { $0.modified > since }
    }

    func scan(folder: URL) -> AsyncThrowingStream<ScanEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ScanEvent.self, throwing: (any Error).self)
        let task = Task {
            do {
                try run(root: Self.canonical(folder), into: continuation)
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func run(root: URL, into continuation: AsyncThrowingStream<ScanEvent, any Error>.Continuation) {
        do {
            let files = try listFiles(in: root)
            continuation.yield(.filesFound(files.count))
            let claimed = claimedPaths(among: files, root: root)
            var seen = Set<GameID>()

            for file in files {
                try Task.checkCancellation()
                defer { continuation.yield(.fileChecked) }
                guard !claimed.contains(file.url.path.lowercased()), let record = try record(for: file, root: root),
                      seen.insert(record.id).inserted else { continue }
                continuation.yield(.gameFound(record))
            }
            continuation.yield(.finished)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func listFiles(in root: URL) throws -> [FileEntry] {
        var rootFailure: (any Error)?
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) { url, error in
            if url.path == root.path {
                rootFailure = error
                return false
            }
            LibraryLog.logger.error("enumerate failed: \(error.localizedDescription)")
            return true
        }

        var files: [FileEntry] = []
        while let url = enumerator?.nextObject() as? URL {
            do {
                let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
                guard values.isRegularFile == true,
                      let size = values.fileSize,
                      let modified = values.contentModificationDate
                else { continue }
                files.append(FileEntry(url: url, size: Int64(size), modified: modified))
            } catch {
                LibraryLog.logger.error("attributes unreadable: \(error.localizedDescription)")
            }
        }

        if let rootFailure {
            throw Self.libraryError(for: rootFailure, path: root.path)
        }
        return files.sorted { $0.url.path < $1.url.path }
    }

    private static func canonical(_ folder: URL) throws -> URL {
        guard let path = try folder.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath else {
            throw LibraryError.folderMissing(path: folder.path)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func libraryError(for error: any Error, path: String) -> any Error {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let isDenied = nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.fileReadNoPermission.rawValue
            && underlying?.domain == NSPOSIXErrorDomain
            && underlying?.code == Int(EPERM)
        return isDenied ? LibraryError.accessDenied(path: path, location: nil) : error
    }

    private func claimedPaths(among files: [FileEntry], root: URL) -> Set<String> {
        var claimed = Set<String>()
        for file in files {
            let directory = file.url.deletingLastPathComponent()
            let names: [String]
            do {
                switch file.url.pathExtension.lowercased() {
                case "cue": names = try DiscSheet.cueFileNames(at: file.url)
                case "m3u": names = try DiscSheet.playlistEntries(at: file.url)
                default: continue
                }
            } catch {
                LibraryLog.logger.error("sheet unreadable: \(error.localizedDescription)")
                continue
            }
            for name in names {
                if let target = Self.resolve(name, from: directory, within: root) {
                    claimed.insert(target.path.lowercased())
                }
            }
        }
        return claimed
    }

    private static func resolve(_ name: String, from directory: URL, within root: URL) -> URL? {
        var components: [Substring] = []
        let combined = directory.path + "/" + name.replacingOccurrences(of: "\\", with: "/")
        for part in combined.split(separator: "/") {
            if part == ".." {
                _ = components.popLast()
            } else if part != "." {
                components.append(part)
            }
        }
        let path = "/" + components.joined(separator: "/")
        guard path.hasPrefix(root.path + "/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: false)
    }

    private func record(for file: FileEntry, root: URL) throws -> GameRecord? {
        let fileExtension = file.url.pathExtension.lowercased()
        do {
            if fileExtension == "zip" {
                return try zippedRecord(for: file)
            }
            guard let system = Self.systemsByExtension[fileExtension] else { return nil }
            switch fileExtension {
            case "cue": return try discRecord(for: file, root: root)
            case "m3u": return try playlistRecord(for: file, root: root)
            case "chd", "pbp": return try digestRecord(for: file, system: system, kind: .file)
            case "iso", "xiso": return try xboxRecord(for: file)
            default: return try cartridgeRecord(for: file, system: system)
            }
        } catch let error as GameDatabaseError {
            throw error
        } catch {
            LibraryLog.logger.error("skipped unreadable file: \(error.localizedDescription)")
            return nil
        }
    }

    private func cartridgeRecord(for file: FileEntry, system: GameSystem) throws -> GameRecord {
        let crcs = try FileDigest.cartridgeCRCs(of: file.url, system: system)
        return try cartridgeRecord(for: file, system: system, crcs: crcs, kind: .file)
    }

    private func zippedRecord(for file: FileEntry) throws -> GameRecord? {
        let entry: ZipEntry
        do {
            guard let inspected = try ZipArchive.inspect(file.url) else { return nil }
            entry = inspected
        } catch let error as ZipError {
            LibraryLog.logger.error("zip skipped: \(String(describing: error))")
            return nil
        }
        let entryExtension = URL(fileURLWithPath: entry.name).pathExtension.lowercased()
        guard let system = Self.systemsByExtension[entryExtension], system != .ps1, system != .xbox else { return nil }
        return try cartridgeRecord(for: file, system: system, crcs: [entry.crc32], kind: .zipped(entryName: entry.name))
    }

    private func cartridgeRecord(
        for file: FileEntry,
        system: GameSystem,
        crcs: [UInt32],
        kind: ContentKind
    ) throws -> GameRecord {
        for crc in crcs {
            if let name = try database.name(system: system, crc: crc) {
                return makeRecord(file, system, .crc32(crc), name, kind)
            }
        }
        let digest = try FileDigest.identityDigest(of: file.url)
        return makeRecord(file, system, .digest(digest), nil, kind)
    }

    private func digestRecord(for file: FileEntry, system: GameSystem, kind: ContentKind) throws -> GameRecord {
        try makeRecord(file, system, .digest(FileDigest.identityDigest(of: file.url)), nil, kind)
    }

    private func discRecord(for file: FileEntry, root: URL) throws -> GameRecord {
        let serial = try serial(ofCue: file.url, root: root)
        return try discRecord(for: file, serial: serial, kind: .disc(cuePath: file.url.path))
    }

    private func playlistRecord(for file: FileEntry, root: URL) throws -> GameRecord? {
        let directory = file.url.deletingLastPathComponent()
        let discs = try DiscSheet.playlistEntries(at: file.url).compactMap { name -> URL? in
            guard let url = Self.resolve(name, from: directory, within: root),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { return nil }
            return url
        }
        guard let first = discs.first else { return nil }

        let serial = first.pathExtension.lowercased() == "cue" ? try serial(ofCue: first, root: root) : nil
        let kind = ContentKind.multiDisc(
            cuePaths: discs.map(\.path),
            labels: discs.indices.map { "Disc \($0 + 1)" }
        )
        return try discRecord(for: file, serial: serial, digestSource: first, kind: kind)
    }

    private func discRecord(
        for file: FileEntry,
        serial: String?,
        digestSource: URL? = nil,
        kind: ContentKind
    ) throws -> GameRecord {
        guard let serial else {
            let digest = try FileDigest.identityDigest(of: digestSource ?? file.url)
            return makeRecord(file, .ps1, .digest(digest), nil, kind)
        }
        return try makeRecord(file, .ps1, .serial(serial), database.name(system: .ps1, serial: serial), kind)
    }

    private func xboxRecord(for file: FileEntry) throws -> GameRecord? {
        let started = ContinuousClock.now
        let disc: XboxDiscInfo
        do {
            disc = try XboxDiscInfo.read(from: file.url, fileSize: UInt64(clamping: file.size))
        } catch let error as XboxDiscError {
            LibraryLog.logger.error("xbox-skipped file=\(file.url.lastPathComponent) reason=\(error.logReason)")
            return nil
        }
        let serial = disc.serial
        let entry = try serial.flatMap { try database.name(system: .xbox, serial: $0) }
        let name = entry ?? (disc.titleName.isEmpty ? nil : disc.titleName)
        let milliseconds = Int(started.duration(to: .now).seconds * 1000)
        LibraryLog.logger.info(
            "xbox-identified file=\(file.url.lastPathComponent) title-id=\(String(format: "%08X", disc.titleID)) "
                + "version=\(String(format: "%08X", disc.version)) serial=\(serial ?? "none") "
                + "entry=\"\(entry ?? "none")\" ms=\(milliseconds)"
        )
        return makeRecord(file, .xbox, .xbe(titleID: disc.titleID, version: disc.version), name, .file)
    }

    private func serial(ofCue cue: URL, root: URL) throws -> String? {
        guard let trackName = try DiscSheet.firstDataTrackFileName(at: cue),
              let track = Self.resolve(trackName, from: cue.deletingLastPathComponent(), within: root),
              (try? track.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        else { return nil }
        return try PS1Serial.read(from: track)
    }

    private func makeRecord(
        _ file: FileEntry,
        _ system: GameSystem,
        _ identity: GameIdentity,
        _ databaseName: String?,
        _ kind: ContentKind
    ) -> GameRecord {
        let parts = databaseName.map(TitleFormatter.parts(ofDatabaseName:))
            ?? TitleFormatter.parts(ofFileName: file.url.lastPathComponent)
        return GameRecord(
            id: GameID(system: system, identity: identity),
            system: system,
            title: parts.title,
            databaseName: databaseName,
            fileURL: file.url,
            kind: kind,
            fileSize: file.size,
            artStatus: .unknown
        )
    }
}
