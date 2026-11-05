import Foundation

@MainActor
final class SlotStore {
    private struct StagedMove {
        let staged: URL
        let destination: URL
    }

    private static let indexVersion = 1

    private let fileManager = FileManager.default
    private let encoder = HubFiles.makeEncoder()
    private let decoder = HubFiles.makeDecoder()

    func slots(for id: GameID, legacyManualStateAt: Date?) -> [SlotNumber: SlotRecord] {
        migrateLegacyState(for: id, legacyManualStateAt: legacyManualStateAt)
        let records = loadRecords(for: id) ?? []
        return Dictionary(records.map { ($0.number, $0) }) { _, last in last }
    }

    func stagingURLs(_ slot: SlotNumber, for id: GameID) -> (state: URL, thumbnail: URL) {
        StoragePaths.slotStaging(slot, for: id)
    }

    func commit(_ slot: SlotNumber, for id: GameID, savedAt: Date, core: String) throws(StoreWriteError) {
        let staging = StoragePaths.slotStaging(slot, for: id)
        let hasThumbnail = fileManager.fileExists(atPath: staging.thumbnail.path)
        let thumbnail = StoragePaths.slotThumbnail(slot, for: id)
        var moves = [StagedMove(staged: staging.state, destination: StoragePaths.slotState(slot, for: id))]
        var removals: [URL] = []
        if hasThumbnail {
            moves.append(StagedMove(staged: staging.thumbnail, destination: thumbnail))
        } else {
            removals.append(thumbnail)
        }
        let record = SlotRecord(number: slot, savedAt: savedAt, core: core, hasThumbnail: hasThumbnail)
        let records = (loadRecords(for: id) ?? []).filter { $0.number != slot } + [record]
        try replace(moves: moves, removals: removals, records: records, for: id)
    }

    func discardStaging(_ slot: SlotNumber, for id: GameID) {
        let staging = StoragePaths.slotStaging(slot, for: id)
        for url in [staging.state, staging.thumbnail] {
            remove(url)
        }
    }

    func stateURL(_ slot: SlotNumber, for id: GameID) -> URL {
        StoragePaths.slotState(slot, for: id)
    }

    func thumbnailURL(_ slot: SlotNumber, for id: GameID) -> URL? {
        guard loadRecords(for: id)?.contains(where: { $0.number == slot && $0.hasThumbnail }) == true else {
            return nil
        }
        return StoragePaths.slotThumbnail(slot, for: id)
    }

    func attachThumbnail(_ slot: SlotNumber, for id: GameID) throws(StoreWriteError) {
        let staged = StoragePaths.slotStaging(slot, for: id).thumbnail
        guard var records = loadRecords(for: id),
              let position = records.firstIndex(where: { $0.number == slot }),
              fileManager.fileExists(atPath: staged.path)
        else { throw .writeFailed }
        let current = records[position]
        records[position] = SlotRecord(
            number: current.number,
            savedAt: current.savedAt,
            core: current.core,
            hasThumbnail: true
        )
        let move = StagedMove(staged: staged, destination: StoragePaths.slotThumbnail(slot, for: id))
        try replace(moves: [move], removals: [], records: records, for: id)
    }

    func newestSavedAt(for id: GameID, legacyManualStateAt: Date?) -> Date? {
        migrateLegacyState(for: id, legacyManualStateAt: legacyManualStateAt)
        return loadRecords(for: id)?.map(\.savedAt).max()
    }

    private func loadRecords(for id: GameID) -> [SlotRecord]? {
        let url = StoragePaths.slotIndex(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            return try decoder.decode(SlotIndexFile.self, from: Data(contentsOf: url)).slots
        } catch {
            LibraryLog.logger.error("slot-index-unreadable game=\(id.rawValue) error=\(error.localizedDescription)")
            return nil
        }
    }

    private func writeIndex(_ records: [SlotRecord], for id: GameID) throws {
        let url = StoragePaths.slotIndex(for: id)
        let file = SlotIndexFile(version: Self.indexVersion, slots: records.sorted { $0.number < $1.number })
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    private func migrateLegacyState(for id: GameID, legacyManualStateAt: Date?) {
        let legacy = StoragePaths.manualState(for: id)
        guard let first = SlotNumber(1),
              fileManager.fileExists(atPath: legacy.path),
              let records = loadRecords(for: id),
              !records.contains(where: { $0.number == first })
        else { return }
        let destination = StoragePaths.slotState(first, for: id)
        let folder = destination.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: destination.path) else {
            LibraryLog.logger.error("slots-migrate-skipped game=\(id.rawValue) reason=slot-1-file-exists")
            return
        }
        do {
            let modified = try legacy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard let savedAt = legacyManualStateAt ?? modified else {
                LibraryLog.logger.error("slots-migrate-skipped game=\(id.rawValue) reason=no-date")
                return
            }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacy, to: destination)
            let record = SlotRecord(number: first, savedAt: savedAt, core: id.system.coreFileName, hasThumbnail: false)
            do {
                try writeIndex(records + [record], for: id)
            } catch {
                restoreLegacy(from: destination, to: legacy)
                throw error
            }
            LibraryLog.logger.info("slots-migrated game=\(id.rawValue)")
        } catch {
            LibraryLog.logger.error("slots-migrate-failed game=\(id.rawValue) error=\(error.localizedDescription)")
        }
    }

    private func restoreLegacy(from slotFile: URL, to legacy: URL) {
        do {
            try fileManager.moveItem(at: slotFile, to: legacy)
        } catch {
            LibraryLog.logger.error("slots-migrate-rollback-failed error=\(error.localizedDescription)")
        }
    }

    private func replace(
        moves: [StagedMove],
        removals: [URL],
        records: [SlotRecord],
        for id: GameID
    ) throws(StoreWriteError) {
        var asides: [(original: URL, aside: URL)] = []
        var placed: [URL] = []
        do {
            let targets = moves.map(\.destination) + removals
            for destination in targets where fileManager.fileExists(atPath: destination.path) {
                let aside = destination.deletingLastPathComponent()
                    .appending(path: ".replaced-\(destination.lastPathComponent)", directoryHint: .notDirectory)
                try removeIfPresent(aside)
                try fileManager.moveItem(at: destination, to: aside)
                asides.append((destination, aside))
            }
            for move in moves {
                try fileManager.moveItem(at: move.staged, to: move.destination)
                placed.append(move.destination)
            }
            try writeIndex(records, for: id)
        } catch {
            rollBack(asides: asides, placed: placed)
            LibraryLog.logger.error("slot-commit-failed game=\(id.rawValue) error=\(error.localizedDescription)")
            throw HubFiles.storeWriteError(from: error)
        }
        for entry in asides {
            remove(entry.aside)
        }
    }

    private func rollBack(asides: [(original: URL, aside: URL)], placed: [URL]) {
        for url in placed {
            remove(url)
        }
        for entry in asides.reversed() {
            do {
                try fileManager.moveItem(at: entry.aside, to: entry.original)
            } catch {
                LibraryLog.logger.error("slot-rollback-failed error=\(error.localizedDescription)")
            }
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func remove(_ url: URL) {
        do {
            try removeIfPresent(url)
        } catch {
            LibraryLog.logger.error("slot-cleanup-failed error=\(error.localizedDescription)")
        }
    }
}
