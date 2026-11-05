import Foundation

@MainActor
final class SessionCheats {
    let game: GameRecord

    private let database: CheatDatabase
    private let store: CheatSettingsStore
    private(set) var cachedLookup: CheatLookup?
    var lastTarget: CheatTarget?

    init(game: GameRecord, database: CheatDatabase, store: CheatSettingsStore) {
        self.game = game
        self.database = database
        self.store = store
    }

    var lookup: CheatLookup {
        get async {
            if let cachedLookup {
                return cachedLookup
            }
            let lookup = await database.cheats(for: game)
            cachedLookup = lookup
            return lookup
        }
    }

    var settings: CheatSettings {
        store.settings(for: game.id)
    }

    func save(_ settings: CheatSettings) throws(StoreWriteError) {
        try store.save(settings, for: game.id)
    }

    func enabledCount(in settings: CheatSettings) -> Int {
        let known = cachedLookup.map { lookup in
            lookup.entries.count { settings.enabled.contains($0.key.rawValue) }
        } ?? settings.enabled.count
        return known + settings.myCodes.count { $0.isEnabled }
    }

    func codes(for settings: CheatSettings, in lookup: CheatLookup) -> [String] {
        let database = lookup.entries.filter { settings.enabled.contains($0.key.rawValue) }.map(\.code)
        let mine = settings.myCodes.filter(\.isEnabled).sorted { $0.addedAt < $1.addedAt }.map(\.code)
        return database + mine
    }

    func codeCount(of codes: [String]) -> Int {
        codes.reduce(0) { $0 + CheatCodeFormat.codeCount($1, for: game.system) }
    }

    func apply(_ settings: CheatSettings, to session: any PlaySessionControlling) async throws {
        guard game.system.playFeatures.contains(.cheats) else { return }
        try await session.setCheats(codes(for: settings, in: lookup))
    }
}
