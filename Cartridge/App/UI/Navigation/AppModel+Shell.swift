import Foundation

extension AppModel {
    private static let collectionLimit = 40
    private static let secondsPerDay: TimeInterval = 86400

    var consoleSummaries: [ConsoleSummary] {
        let library = dependencies.library
        let resuming = Set(library.continuePlaying().map(\.id))
        return GameSystem.allCases.sorted { $0.libraryOrder < $1.libraryOrder }.compactMap { system in
            let games = library.games(in: system)
            guard !games.isEmpty else { return nil }
            return ConsoleSummary(
                system: system,
                gameCount: games.count,
                inProgress: games.count { resuming.contains($0.id) },
                covers: Array(games.prefix(3))
            )
        }
    }

    var homeRows: [HomeRow] {
        let library = dependencies.library
        var rows: [HomeRow] = []
        let resuming = library.continuePlaying()
        if !resuming.isEmpty {
            rows.append(HomeRow(kind: .continuePlaying, items: resuming.map(HomeItem.game)))
        }
        let favorites = library.favorites().prefix(Self.collectionLimit)
        if !favorites.isEmpty {
            rows.append(HomeRow(kind: .favorites, items: favorites.map(HomeItem.game)))
        }
        let all = allGames
        let seed = dailySeed
        if let pick = tonightsPick(from: all, excluding: Set(resuming.map(\.id)), seed: seed) {
            rows.append(HomeRow(kind: .pick, items: [.game(pick)]))
        }
        let consoles = consoleSummaries
        if !consoles.isEmpty {
            rows.append(HomeRow(kind: .consoles, items: consoles.map(HomeItem.console)))
        }
        for kind in [HomeRowKind.eighties, .nineties, .noughties] {
            let games = dailyWindow(
                of: all.filter { matches(kind, game: $0, metadata: library.metadata(for: $0)) },
                seed: seed
            )
            if !games.isEmpty {
                rows.append(HomeRow(kind: kind, items: games.map(HomeItem.game)))
            }
        }
        return rows
    }

    var searchResults: [GameRecord] {
        let terms = Self.searchWords(shell.search.query)
        guard !terms.isEmpty else { return [] }
        return allGames.filter { game in
            let words = Self.searchWords(game.title)
            return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
        }
    }

    private static func searchWords(_ text: String) -> [Substring] {
        text.uppercased().split { !$0.isLetter && !$0.isNumber }
    }

    func moment(for game: GameRecord) async -> BackdropSource {
        if let frame = await resumeFrame(for: game) {
            return .screenshot(frame)
        }
        return await backdrop(for: game)
    }

    func resumeFrame(for game: GameRecord) async -> LoadedArt? {
        let url = StoragePaths.resumeSnapshot(for: game.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return await ArtDecoder.decode(url)
    }

    func consoleGames(_ system: GameSystem) -> [GameRecord] {
        dependencies.library.games(in: system)
    }

    private var allGames: [GameRecord] {
        GameSystem.allCases.sorted { $0.libraryOrder < $1.libraryOrder }
            .flatMap { dependencies.library.games(in: $0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var dailySeed: Int {
        let now = Date.now
        let local = now.timeIntervalSince1970 + TimeInterval(TimeZone.current.secondsFromGMT(for: now))
        // The pick and the decade rows change at 5 pm local time.
        return Int((local - 17 * 3600) / Self.secondsPerDay)
    }

    private func tonightsPick(from games: [GameRecord], excluding: Set<GameID>, seed: Int) -> GameRecord? {
        let candidates = games.filter { !excluding.contains($0.id) }
        guard !candidates.isEmpty else { return nil }
        return candidates[(seed &* 7919) % candidates.count]
    }

    private func dailyWindow(of games: [GameRecord], seed: Int) -> [GameRecord] {
        guard games.count > Self.collectionLimit else { return games }
        let start = (seed &* 7919) % games.count
        let end = start + Self.collectionLimit
        guard end > games.count else { return Array(games[start..<end]) }
        return Array(games[start...] + games[..<(end - games.count)])
    }

    private func matches(_ kind: HomeRowKind, game: GameRecord, metadata: GameMetadata?) -> Bool {
        switch kind {
        case .eighties: (1980...1989).contains(metadata?.year ?? 0)
        case .nineties: (1990...1999).contains(metadata?.year ?? 0)
        case .noughties: (2000...2009).contains(metadata?.year ?? 0) || game.system == .xbox
        case .continuePlaying, .favorites, .group, .pick, .consoles: false
        }
    }
}

extension AppModel {
    func handleShell(_ event: NavigationEvent) {
        if let viewer = shell.gallery.viewer {
            handleViewer(event, viewer: viewer)
            return
        }
        if case .section(let direction) = event.action {
            switchSection(direction)
            return
        }
        if event.action == .options {
            showSettings()
            return
        }
        if let focus = shell.barFocus {
            handleBar(event, focus: focus)
            return
        }
        handlePage(event)
    }

    private func handlePage(_ event: NavigationEvent) {
        switch shell.section {
        case .home: handleHomeRows(event)
        case .favorites: handleFavorites(event)
        case .consoles:
            if let system = shell.console {
                handleGrid(event, system: system)
            } else {
                handleShelf(event)
            }
        case .gallery: handleGallery(event)
        case .search: handleSearch(event)
        case .settings: break
        }
    }

    func switchSection(_ direction: Direction) {
        let current = route == .settings ? ShellSection.settings : shell.section
        let target = current.stepped(direction)
        guard target != current else { return }
        if shell.barFocus != nil {
            shell.barFocus = target
        }
        activate(target)
    }

    func activate(_ section: ShellSection) {
        if section == .settings {
            if route != .settings {
                show(.settings)
            }
            return
        }
        if route == .settings {
            show(.library)
        }
        if section == .consoles, shell.section != .consoles {
            shell.console = nil
        }
        shell.section = section
    }

    private func handleBar(_ event: NavigationEvent, focus: ShellSection) {
        switch event.action {
        case .move(.left), .move(.right):
            let direction: Direction = event.action == .move(.left) ? .left : .right
            let target = focus.stepped(direction)
            shell.barFocus = target
        case .confirm:
            shell.barFocus = nil
            activate(focus)
        case .move(.down), .back:
            shell.barFocus = nil
        case .move, .options, .secondary, .pause, .section, .text, .erase:
            break
        }
    }

    private func handleHomeRows(_ event: NavigationEvent) {
        if event.action == .secondary {
            if canRemoveFromContinue, let game = shell.home.slot(in: homeRows)?.item.game {
                removeFromContinue(game)
            }
            return
        }
        handleRows(event, rows: homeRows, cursor: \.home, section: .home)
    }

    func handleRows(
        _ event: NavigationEvent,
        rows: [HomeRow],
        cursor: WritableKeyPath<ShellState, HomeCursor>,
        section: ShellSection
    ) {
        switch event.action {
        case .move(let direction):
            if !shell[keyPath: cursor].move(direction, in: rows), direction == .up {
                shell.barFocus = section
            }
        case .confirm:
            guard let slot = shell[keyPath: cursor].slot(in: rows) else { return }
            switch slot.item {
            case .game(let game):
                show(.gamePanel(game.id))
            case .console(let summary):
                shell.section = .consoles
                shell.console = summary.system
            }
        case .back:
            shell.barFocus = section
        case .options, .secondary, .pause, .section, .text, .erase:
            break
        }
    }

    private func handleShelf(_ event: NavigationEvent) {
        let consoles = consoleSummaries
        guard !consoles.isEmpty else {
            if event.action == .back || event.action == .move(.up) {
                shell.barFocus = .consoles
            }
            return
        }
        shell.shelfIndex = min(shell.shelfIndex, consoles.count - 1)
        switch event.action {
        case .move(.left):
            shell.shelfIndex = (shell.shelfIndex + consoles.count - 1) % consoles.count
        case .move(.right):
            shell.shelfIndex = (shell.shelfIndex + 1) % consoles.count
        case .move(.up):
            shell.barFocus = .consoles
        case .confirm:
            shell.console = consoles[shell.shelfIndex].system
        case .back:
            activate(.home)
        case .move, .options, .secondary, .pause, .section, .text, .erase:
            break
        }
    }

    private func handleGrid(_ event: NavigationEvent, system: GameSystem) {
        let games = consoleGames(system)
        let index = min(shell.grid[system] ?? 0, max(0, games.count - 1))
        switch event.action {
        case .move(let direction):
            switch GridMath.step(index, direction, count: games.count, columns: shell.gridColumns) {
            case .moved(let target): shell.grid[system] = target
            case .topEdge: shell.barFocus = .consoles
            case .leftEdge, .blocked: break
            }
        case .confirm:
            if games.indices.contains(index) {
                show(.gamePanel(games[index].id))
            }
        case .back:
            shell.console = nil
            if let position = consoleSummaries.firstIndex(where: { $0.system == system }) {
                shell.shelfIndex = position
            }
        case .options, .secondary, .pause, .section, .text, .erase:
            break
        }
    }

    private func handleGallery(_ event: NavigationEvent) {
        let items = dependencies.gallery.items
        guard !items.isEmpty else {
            if event.action == .back || event.action == .move(.up) {
                shell.barFocus = .gallery
            }
            return
        }
        let index = min(shell.gallery.index, items.count - 1)
        switch event.action {
        case .move(let direction):
            switch GridMath.step(index, direction, count: items.count, columns: shell.gallery.columns) {
            case .moved(let target): shell.gallery.index = target
            case .topEdge: shell.barFocus = .gallery
            case .leftEdge, .blocked: break
            }
        case .confirm:
            shell.gallery.index = index
            shell.gallery.viewer = GalleryViewerModel(item: items[index], store: dependencies.gallery)
        case .back:
            shell.barFocus = .gallery
        case .options, .secondary, .pause, .section, .text, .erase:
            break
        }
    }

    private func handleViewer(_ event: NavigationEvent, viewer: GalleryViewerModel) {
        let items = dependencies.gallery.items
        let position = items.firstIndex { $0.id == viewer.item.id }
        guard let exit = viewer.handle(event.action) else { return }
        viewer.stop()
        shell.gallery.viewer = nil
        switch exit {
        case .closed:
            if let position = dependencies.gallery.items.firstIndex(where: { $0.id == viewer.item.id }) {
                shell.gallery.index = position
            }
        case .deleted:
            if let position {
                shell.gallery.index = position
            }
        }
    }
}
