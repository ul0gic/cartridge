import Foundation

actor FavoritesFile {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func read() -> [String: Date] {
        guard FileManager.default.fileExists(atPath: StoragePaths.favorites.path) else { return [:] }
        do {
            return try decoder.decode([String: Date].self, from: Data(contentsOf: StoragePaths.favorites))
        } catch {
            LibraryLog.logger.error("favorites unreadable: \(error.localizedDescription)")
            return [:]
        }
    }

    func write(_ favorites: [String: Date]) throws {
        try FileManager.default.createDirectory(at: StoragePaths.root, withIntermediateDirectories: true)
        try encoder.encode(favorites).write(to: StoragePaths.favorites, options: .atomic)
    }
}

extension LibraryStore {
    func favorites() -> [GameRecord] {
        guard !favoriteDates.isEmpty, let games = index?.games else { return [] }
        return games
            .compactMap { game in favoriteDates[game.id.rawValue].map { (game, $0) } }
            .sorted { ($0.1, $1.0.id.rawValue) > ($1.1, $0.0.id.rawValue) }
            .map(\.0)
    }

    func isFavorite(_ id: GameID) -> Bool {
        favoriteDates[id.rawValue] != nil
    }

    func setFavorite(_ isFavorite: Bool, for id: GameID) {
        favoriteDates[id.rawValue] = isFavorite ? .now : nil
        let previous = favoritesWrite
        favoritesWrite = Task {
            await previous?.value
            do {
                try await favoritesFile.write(favoriteDates)
            } catch {
                LibraryLog.logger.error("favorites write failed: \(error.localizedDescription)")
            }
        }
    }

    func loadFavorites() async {
        favoriteDates = await favoritesFile.read()
    }
}
