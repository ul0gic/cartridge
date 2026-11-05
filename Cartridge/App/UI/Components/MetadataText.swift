import Foundation

enum MetadataText {
    static func line(_ metadata: GameMetadata?) -> String? {
        guard let metadata else { return nil }
        let parts = [
            metadata.year.map { String($0) },
            metadata.genre,
            metadata.developer ?? metadata.publisher,
            metadata.players.map(players),
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func players(_ count: Int) -> String {
        count <= 1 ? "1 player" : "1–\(count) players"
    }
}
