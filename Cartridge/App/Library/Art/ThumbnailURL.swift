import Foundation

enum ThumbnailKind: String {
    case boxart = "Named_Boxarts"
    case snap = "Named_Snaps"
    case title = "Named_Titles"
}

enum ThumbnailURL {
    private static let host = "thumbnails.libretro.com"
    private static let replacedCharacters = Set("&*/:`<>?\\|\"")
    private static let xboxReplacedCharacters = replacedCharacters.subtracting("&")

    static func candidates(for game: GameRecord, kind: ThumbnailKind) -> [URL] {
        names(for: game).compactMap { url(named: $0, system: game.system, kind: kind) }
    }

    private static func url(named name: String, system: GameSystem, kind: ThumbnailKind) -> URL? {
        let replaced = system == .xbox ? xboxReplacedCharacters : replacedCharacters
        let fileName = String(name.map { replaced.contains($0) ? "_" : $0 })
        let segments = [system.databaseFolder, kind.rawValue, "\(fileName).png"]
        let encoded = segments.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        guard encoded.count == segments.count else { return nil }
        return URL(string: "https://\(host)/" + encoded.joined(separator: "/"))
    }

    private static func names(for game: GameRecord) -> [String] {
        let name = artName(for: game)
        guard game.system == .xbox else { return [name] }
        let fallback = name
            .replacing(/\s\((?:USA|World)[^)]*\)/, with: " (USA)", maxReplacements: 1)
            .replacing(/\s\((?:[A-Z][a-z],)*[A-Z][a-z]\)/, with: "")
            .replacing(/\s\(Rev \d+\)/, with: "")
        return fallback == name ? [name] : [name, fallback]
    }

    private static func artName(for game: GameRecord) -> String {
        if let databaseName = game.databaseName {
            return databaseName
        }
        let stem = game.fileURL.deletingPathExtension().lastPathComponent
        let spaced = stem.replacingOccurrences(of: "_", with: " ")
        return spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
