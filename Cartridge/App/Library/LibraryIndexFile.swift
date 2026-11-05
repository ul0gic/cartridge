import Foundation

actor LibraryIndexFile {
    static let currentVersion = 1

    func read() throws -> LibraryIndex? {
        guard FileManager.default.fileExists(atPath: StoragePaths.libraryIndex.path) else { return nil }
        let data = try Data(contentsOf: StoragePaths.libraryIndex)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(LibraryIndex.self, from: data)
        guard index.version == Self.currentVersion else { throw LibraryError.indexUnreadable }
        return index
    }

    func write(_ index: LibraryIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try FileManager.default.createDirectory(at: StoragePaths.root, withIntermediateDirectories: true)
        try data.write(to: StoragePaths.libraryIndex, options: .atomic)
    }
}
