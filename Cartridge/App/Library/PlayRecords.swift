import Foundation

actor PlayRecordFiles {
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

    func readAll(_ ids: [GameID]) -> [GameID: PlayRecord] {
        var records: [GameID: PlayRecord] = [:]
        for id in ids {
            let url = StoragePaths.playRecord(for: id)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                records[id] = try decoder.decode(PlayRecord.self, from: Data(contentsOf: url))
            } catch {
                LibraryLog.logger.error("play record unreadable: \(error.localizedDescription)")
            }
        }
        return records
    }

    func write(_ record: PlayRecord, for id: GameID) throws {
        let url = StoragePaths.playRecord(for: id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(record).write(to: url, options: .atomic)
    }
}

extension PlayRecord {
    var isHiddenFromContinue: Bool {
        continueHiddenAt.map { $0 >= (lastPlayedAt ?? .distantPast) } ?? false
    }
}

extension LibraryStore {
    private static let continuePlayingLimit = 10

    func playRecord(for id: GameID) -> PlayRecord? {
        playRecords[id]
    }

    func recordPlay(_ record: PlayRecord, for id: GameID) async {
        playRecords[id] = record
        do {
            try await playFiles.write(record, for: id)
        } catch {
            LibraryLog.logger.error("play record write failed: \(error.localizedDescription)")
        }
    }

    func continuePlaying() -> [GameRecord] {
        guard let games = index?.games else { return [] }
        return playRecords
            .filter { $0.value.resumeStateAt != nil && !$0.value.isHiddenFromContinue }
            .sorted {
                ($0.value.lastPlayedAt ?? .distantPast, $1.key.rawValue)
                    > ($1.value.lastPlayedAt ?? .distantPast, $0.key.rawValue)
            }
            .compactMap { positions[$0.key].map { games[$0] } }
            .prefix(Self.continuePlayingLimit)
            .map(\.self)
    }

    func loadPlayRecords() async {
        guard let ids = index?.games.map(\.id) else { return }
        let loaded = await playFiles.readAll(ids)
        playRecords.merge(loaded) { _, fresh in fresh }
    }
}
