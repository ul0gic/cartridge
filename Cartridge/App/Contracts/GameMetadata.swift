struct GameMetadata: Codable, Hashable, Sendable {
    let year: Int?
    let genre: String?
    let developer: String?
    let publisher: String?
    let players: Int?
    let summary: String?
}
