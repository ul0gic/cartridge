import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore: LibraryStoring {
    private static let writeDelay = Duration.seconds(2)
    private static let finishedScanVisibility = Duration.seconds(1)

    private(set) var index: LibraryIndex?
    private(set) var scan: ScanProgress?
    private(set) var error: LibraryError?
    var playRecords: [GameID: PlayRecord] = [:]
    var favoriteDates: [String: Date] = [:]

    @ObservationIgnored let playFiles = PlayRecordFiles()
    @ObservationIgnored let favoritesFile = FavoritesFile()
    @ObservationIgnored var favoritesWrite: Task<Void, Never>?
    @ObservationIgnored private(set) var positions: [GameID: Int] = [:]
    @ObservationIgnored private let scanner: LibraryScanner
    @ObservationIgnored private let database: GameDatabase
    @ObservationIgnored private var metadataCache: [GameID: GameMetadata?] = [:]
    @ObservationIgnored private let indexFile = LibraryIndexFile()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var sortedBySystem: [GameSystem: [GameRecord]] = [:]

    init(databaseDirectory: URL? = nil) {
        scanner = LibraryScanner(databaseDirectory: databaseDirectory)
        database = GameDatabase(directory: databaseDirectory)
    }

    func load() async {
        error = nil
        guard let path = UserDefaults.standard.string(forKey: DefaultsKey.romFolderPath.rawValue) else {
            replaceIndex(nil)
            return
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)

        await Task.detached { Self.wipeScratch() }.value
        let stored = await readIndex()
        var usable = stored?.romFolderPath == path ? stored : nil
        if let games = usable?.games {
            usable?.games = TitleFormatter.listing(games)
        }
        replaceIndex(usable ?? emptyIndex(for: path))
        warmMetadata()
        await loadPlayRecords()
        await loadFavorites()

        do {
            try await scanner.validate(folder)
            guard let usable else {
                startScan(folder: folder)
                return
            }
            let changed = try await scanner.hasChanged(
                folder: folder,
                fileCount: usable.fileCount,
                since: usable.scannedAt
            )
            if changed {
                startScan(folder: folder)
            }
        } catch let failure as LibraryError {
            error = locating(failure)
        } catch {
            LibraryLog.logger.error("load failed: \(error.localizedDescription)")
        }
    }

    func chooseFolder(_ url: URL) async {
        error = nil
        do {
            try await scanner.validate(url)
        } catch let failure as LibraryError {
            error = failure
            return
        } catch {
            LibraryLog.logger.error("choose failed: \(error.localizedDescription)")
            return
        }
        UserDefaults.standard.set(url.path, forKey: DefaultsKey.romFolderPath.rawValue)
        replaceIndex(emptyIndex(for: url.path))
        await startScan(folder: url).value
    }

    func rescan() async {
        guard let path = index?.romFolderPath else { return }
        error = nil
        await startScan(folder: URL(fileURLWithPath: path, isDirectory: true)).value
    }

    func retry() async {
        await load()
    }

    func games(in system: GameSystem) -> [GameRecord] {
        guard let games = index?.games else { return [] }
        if let cached = sortedBySystem[system] {
            return cached
        }
        let sorted = games
            .filter { $0.system == system }
            .map { (key: TitleFormatter.sortKey($0.title), game: $0) }
            .sorted { ($0.key, $0.game.id.rawValue) < ($1.key, $1.game.id.rawValue) }
            .map(\.game)
        sortedBySystem[system] = sorted
        return sorted
    }

    func saveSelection(_ selection: LibrarySelection) {
        index?.lastSelection = selection
        scheduleWrite()
    }

    func metadata(for game: GameRecord) -> GameMetadata? {
        if let cached = metadataCache[game.id] {
            return cached
        }
        let found: GameMetadata?
        do {
            switch game.id.identity {
            case .crc32(let crc): found = try database.metadata(system: game.system, crc: crc)
            case .serial(let serial): found = try database.metadata(system: game.system, serial: serial)
            case .xbe(let titleID, _):
                let serial = XboxDiscInfo.serial(titleID: titleID)
                found = try serial.flatMap { try database.metadata(system: game.system, serial: $0) }
            case .digest: found = nil
            }
        } catch {
            LibraryLog.logger.error("metadata unavailable: \(error.localizedDescription)")
            return nil
        }
        metadataCache[game.id] = found
        return found
    }

    func protectedLocation(of url: URL) -> ProtectedLocation? {
        ProtectedLocations.location(of: url)
    }

    func updateArtStatus(_ status: ArtStatus, for id: GameID) {
        guard let position = positions[id] else { return }
        index?.games[position].artStatus = status
        sortedBySystem = [:]
        scheduleWrite()
    }

    nonisolated private static func wipeScratch() {
        guard FileManager.default.fileExists(atPath: StoragePaths.scratch.path) else { return }
        do {
            try FileManager.default.removeItem(at: StoragePaths.scratch)
        } catch {
            LibraryLog.logger.error("scratch wipe failed: \(error.localizedDescription)")
        }
    }

    private func warmMetadata() {
        let database = database
        Task.detached(priority: .utility) {
            do {
                try database.preload()
            } catch {
                LibraryLog.logger.error("metadata preload failed: \(error.localizedDescription)")
            }
        }
    }

    private func readIndex() async -> LibraryIndex? {
        do {
            return try await indexFile.read()
        } catch {
            LibraryLog.logger.error("index unreadable: \(error.localizedDescription)")
            return nil
        }
    }

    private func emptyIndex(for path: String) -> LibraryIndex {
        LibraryIndex(
            version: LibraryIndexFile.currentVersion,
            romFolderPath: path,
            scannedAt: .distantPast,
            fileCount: 0,
            games: [],
            lastSelection: nil
        )
    }

    private func replaceIndex(_ newIndex: LibraryIndex?) {
        index = newIndex
        positions = Dictionary(
            uniqueKeysWithValues: (newIndex?.games ?? []).enumerated().map { ($1.id, $0) }
        )
        sortedBySystem = [:]
    }

    private func locating(_ failure: LibraryError) -> LibraryError {
        guard case .accessDenied(let path, _) = failure else { return failure }
        return .accessDenied(path: path, location: protectedLocation(of: URL(fileURLWithPath: path)))
    }

    @discardableResult
    private func startScan(folder: URL) -> Task<Void, Never> {
        let previous = scanTask
        previous?.cancel()
        scan = ScanProgress(
            folderName: folder.lastPathComponent,
            folderPath: folder.path,
            filesFound: 0,
            filesChecked: 0,
            gamesFound: 0,
            perSystem: [:],
            isFinished: false
        )
        let task = Task {
            await previous?.value
            await performScan(folder: folder)
        }
        scanTask = task
        return task
    }

    private func performScan(folder: URL) async {
        let clock = ContinuousClock()
        let started = Date()
        let startInstant = clock.now
        var seen = Set<GameID>()
        var filesFound = 0

        do {
            for try await event in await scanner.scan(folder: folder) {
                guard !Task.isCancelled else { return }
                switch event {
                case .filesFound(let count):
                    filesFound = count
                    scan?.filesFound = count
                case .fileChecked:
                    scan?.filesChecked += 1
                case .gameFound(let record):
                    seen.insert(record.id)
                    scan?.gamesFound += 1
                    scan?.perSystem[record.system, default: 0] += 1
                    merge(record)
                case .finished:
                    let milliseconds = Int((clock.now - startInstant) / .milliseconds(1))
                    await finishScan(seen: seen, fileCount: filesFound, started: started)
                    LibraryLog.logger.info(
                        "scan-finished games=\(seen.count) files=\(filesFound) ms=\(milliseconds)"
                    )
                }
            }
        } catch let failure as LibraryError {
            scan = nil
            error = locating(failure)
        } catch {
            scan = nil
            LibraryLog.logger.error("scan failed: \(error.localizedDescription)")
        }
    }

    private func merge(_ incoming: GameRecord) {
        guard let position = positions[incoming.id] else {
            positions[incoming.id] = index?.games.count ?? 0
            index?.games.append(incoming)
            sortedBySystem = [:]
            return
        }
        guard let existing = index?.games[position] else { return }
        let sameName = existing.databaseName == incoming.databaseName
        index?.games[position] = GameRecord(
            id: incoming.id,
            system: incoming.system,
            title: sameName ? existing.title : incoming.title,
            databaseName: incoming.databaseName,
            fileURL: incoming.fileURL,
            kind: incoming.kind,
            fileSize: incoming.fileSize,
            artStatus: existing.artStatus
        )
        sortedBySystem = [:]
    }

    private func finishScan(seen: Set<GameID>, fileCount: Int, started: Date) async {
        guard var finished = index else { return }
        finished.games = TitleFormatter.listing(finished.games.filter { seen.contains($0.id) })
        finished.fileCount = fileCount
        finished.scannedAt = started
        replaceIndex(finished)
        scan?.isFinished = true

        writeTask?.cancel()
        writeTask = nil
        await writeIndex()
        await loadPlayRecords()

        Task {
            guard await (try? Task.sleep(for: Self.finishedScanVisibility)) != nil else { return }
            if scan?.isFinished == true {
                scan = nil
            }
        }
    }

    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task {
            guard await (try? Task.sleep(for: Self.writeDelay)) != nil else { return }
            await writeIndex()
        }
    }

    private func writeIndex() async {
        guard let index else { return }
        do {
            try await indexFile.write(index)
        } catch {
            LibraryLog.logger.error("index write failed: \(error.localizedDescription)")
        }
    }
}
