import Foundation

enum DiscSheetError: Error {
    case tooLarge
}

enum DiscSheet {
    private static let maxBytes = 1 << 20

    static func cueFileNames(at url: URL) throws -> [String] {
        try lines(of: url).compactMap { quotedFileName(inCueLine: $0) }
    }

    static func firstDataTrackFileName(at url: URL) throws -> String? {
        var currentFile: String?
        for line in try lines(of: url) {
            if let name = quotedFileName(inCueLine: line) {
                currentFile = name
            } else if line.uppercased().hasPrefix("TRACK "), line.uppercased().contains(" MODE"), let currentFile {
                return currentFile
            }
        }
        return nil
    }

    static func playlistEntries(at url: URL) throws -> [String] {
        try lines(of: url).filter { !$0.hasPrefix("#") }
    }

    private static func quotedFileName(inCueLine line: String) -> String? {
        guard line.uppercased().hasPrefix("FILE "),
              let open = line.firstIndex(of: "\""),
              let close = line.lastIndex(of: "\""),
              open < close
        else { return nil }
        let name = line[line.index(after: open)..<close]
        return name.isEmpty ? nil : String(name)
    }

    private static func lines(of url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw DiscSheetError.tooLarge }
        let text = String(data: data, encoding: .utf8) ?? String(data.map { Character(UnicodeScalar($0)) })
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
