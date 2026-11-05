import Foundation

@MainActor
final class CheatSettingsStore {
    private let fileManager = FileManager.default
    private let encoder = HubFiles.makeEncoder()
    private let decoder = HubFiles.makeDecoder()

    func settings(for id: GameID) -> CheatSettings {
        let url = StoragePaths.cheatSettings(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return .empty }
        do {
            return try decoder.decode(CheatSettings.self, from: Data(contentsOf: url))
        } catch {
            LibraryLog.logger.error("cheat-settings-unreadable game=\(id.rawValue) error=\(error.localizedDescription)")
            return .empty
        }
    }

    func save(_ settings: CheatSettings, for id: GameID) throws(StoreWriteError) {
        let url = StoragePaths.cheatSettings(for: id)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(settings).write(to: url, options: .atomic)
        } catch {
            LibraryLog.logger.error("cheat-settings-save-failed game=\(id.rawValue)")
            throw HubFiles.storeWriteError(from: error)
        }
    }
}
