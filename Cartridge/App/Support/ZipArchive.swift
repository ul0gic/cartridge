import Foundation

struct ZipEntry: Sendable, Equatable {
    let name: String
    let uncompressedSize: UInt64
    let crc32: UInt32
}

enum ZipError: Error, Sendable {
    case unreadable
    case multipleEntries(count: Int)
    case tooLarge(bytes: UInt64)
    case extractionFailed(status: Int32)
}

enum ZipArchive {
    private static let endRecordSignature: UInt32 = 0x0605_4B50
    private static let centralRecordSignature: UInt32 = 0x0201_4B50
    private static let endRecordLength = 22
    private static let maxCommentLength = 65535
    private static let maxCentralDirectoryBytes = 16 * 1024 * 1024
    private static let maxEntryBytes: UInt64 = 256 * 1024 * 1024
    private static let utf8NameFlag: UInt16 = 1 << 11
    private static let gameExtensions = Set(GameSystem.allCases.flatMap(\.fileExtensions))

    static func inspect(_ url: URL) throws -> ZipEntry? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let directory = try readCentralDirectory(of: handle)

        var cursor = Cursor(data: directory.data)
        var eligible: [ZipEntry] = []
        for _ in 0..<directory.entryCount {
            guard try cursor.read(UInt32.self) == centralRecordSignature else { throw ZipError.unreadable }
            try cursor.skip(4)
            let flags = try cursor.read(UInt16.self)
            try cursor.skip(6)
            let crc32 = try cursor.read(UInt32.self)
            try cursor.skip(4)
            let uncompressedSize = try cursor.read(UInt32.self)
            let nameLength = try Int(cursor.read(UInt16.self))
            let extraLength = try Int(cursor.read(UInt16.self))
            let commentLength = try Int(cursor.read(UInt16.self))
            try cursor.skip(12)
            let nameBytes = try cursor.bytes(nameLength)
            try cursor.skip(extraLength + commentLength)

            guard flags & utf8NameFlag != 0 || nameBytes.allSatisfy({ $0 < 0x80 }),
                  let name = String(data: nameBytes, encoding: .utf8)
            else { throw ZipError.unreadable }

            if isEligible(name) {
                guard uncompressedSize != UInt32.max else { throw ZipError.unreadable }
                eligible.append(ZipEntry(name: name, uncompressedSize: UInt64(uncompressedSize), crc32: crc32))
            }
        }

        guard let entry = eligible.first else { return nil }
        guard eligible.count == 1 else { throw ZipError.multipleEntries(count: eligible.count) }
        guard entry.uncompressedSize <= maxEntryBytes else { throw ZipError.tooLarge(bytes: entry.uncompressedSize) }
        return entry
    }

    static func extract(_ entry: ZipEntry, from url: URL, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: lastComponent(of: entry.name), directoryHint: .notDirectory)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ZipError.unreadable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, memberPattern(for: entry.name)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            try copy(from: pipe.fileHandleForReading, to: output, process: process, expecting: entry)
        } catch {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    private static func copy(
        from source: FileHandle,
        to output: FileHandle,
        process: Process,
        expecting entry: ZipEntry
    ) throws {
        var checksum = CRC32()
        var written: UInt64 = 0
        while let chunk = try source.read(upToCount: 1 << 20), !chunk.isEmpty {
            written += UInt64(chunk.count)
            guard written <= entry.uncompressedSize else { throw ZipError.tooLarge(bytes: written) }
            try output.write(contentsOf: chunk)
            chunk.withUnsafeBytes { checksum.update($0) }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ZipError.extractionFailed(status: process.terminationStatus)
        }
        guard written == entry.uncompressedSize, checksum.value == entry.crc32 else { throw ZipError.unreadable }
    }

    private static func isEligible(_ name: String) -> Bool {
        guard !name.hasSuffix("/"), !name.hasPrefix("__MACOSX/") else { return false }
        let component = lastComponent(of: name)
        guard !component.hasPrefix("._") else { return false }
        return gameExtensions.contains(URL(fileURLWithPath: component).pathExtension.lowercased())
    }

    private static func lastComponent(of name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    private static func memberPattern(for name: String) -> String {
        var pattern = ""
        for character in name {
            if "\\[]*?".contains(character) {
                pattern.append("\\")
            }
            pattern.append(character)
        }
        return pattern.hasPrefix("-") ? "\\" + pattern : pattern
    }

    private static func readCentralDirectory(of handle: FileHandle) throws -> (entryCount: Int, data: Data) {
        let fileSize = try handle.seekToEnd()
        let tailLength = min(fileSize, UInt64(endRecordLength + maxCommentLength))
        let tailStart = fileSize - tailLength
        try handle.seek(toOffset: tailStart)
        guard let tail = try handle.read(upToCount: Int(tailLength)), tail.count == Int(tailLength) else {
            throw ZipError.unreadable
        }

        guard let endRecord = try findEndRecord(in: tail) else { throw ZipError.unreadable }
        var cursor = Cursor(data: tail, offset: endRecord)
        try cursor.skip(4)
        let diskNumber = try cursor.read(UInt16.self)
        let directoryDisk = try cursor.read(UInt16.self)
        let entriesOnDisk = try cursor.read(UInt16.self)
        let entryCount = try cursor.read(UInt16.self)
        let directorySize = try cursor.read(UInt32.self)
        let directoryOffset = try cursor.read(UInt32.self)

        let isSingleDisk = diskNumber == 0 && directoryDisk == 0 && entriesOnDisk == entryCount
        let usesZip64 = entryCount == UInt16.max || directorySize == UInt32.max || directoryOffset == UInt32.max
        let endRecordOffset = tailStart + UInt64(endRecord)
        guard isSingleDisk, !usesZip64,
              Int(directorySize) <= maxCentralDirectoryBytes,
              UInt64(directoryOffset) + UInt64(directorySize) <= endRecordOffset
        else { throw ZipError.unreadable }

        try handle.seek(toOffset: UInt64(directoryOffset))
        guard let data = try handle.read(upToCount: Int(directorySize)), data.count == Int(directorySize) else {
            throw ZipError.unreadable
        }
        return (Int(entryCount), data)
    }

    private static func findEndRecord(in tail: Data) throws -> Int? {
        guard tail.count >= endRecordLength else { return nil }
        for offset in stride(from: tail.count - endRecordLength, through: 0, by: -1) {
            var cursor = Cursor(data: tail, offset: offset)
            guard try cursor.read(UInt32.self) == endRecordSignature else { continue }
            try cursor.skip(16)
            let commentLength = try cursor.read(UInt16.self)
            if offset + endRecordLength + Int(commentLength) <= tail.count {
                return offset
            }
        }
        return nil
    }
}

private struct Cursor {
    let data: Data
    var offset = 0

    mutating func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        try require(size)
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += size
        return T(littleEndian: value)
    }

    mutating func skip(_ count: Int) throws {
        try require(count)
        offset += count
    }

    mutating func bytes(_ count: Int) throws -> Data {
        try require(count)
        let start = data.startIndex + offset
        offset += count
        return data[start..<start + count]
    }

    private func require(_ count: Int) throws {
        guard count >= 0, offset + count <= data.count else { throw ZipError.unreadable }
    }
}
