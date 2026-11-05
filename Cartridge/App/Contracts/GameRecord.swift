import Foundation

enum ContentKind: Codable, Hashable, Sendable {
    case file
    case zipped(entryName: String)
    case disc(cuePath: String)
    case multiDisc(cuePaths: [String], labels: [String])
}

enum ArtStatus: Codable, Hashable, Sendable {
    case unknown
    case cached
    case missing(since: Date)
}

struct GameRecord: Identifiable, Codable, Hashable, Sendable {
    let id: GameID
    let system: GameSystem
    let title: String
    let databaseName: String?
    let fileURL: URL
    let kind: ContentKind
    let fileSize: Int64
    var artStatus: ArtStatus
}
