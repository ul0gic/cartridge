import Foundation

enum ShellSection: Int, CaseIterable, Hashable {
    case home
    case favorites
    case consoles
    case gallery
    case search
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .favorites: "Favorites"
        case .consoles: "Consoles"
        case .gallery: "Gallery"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    func stepped(_ direction: Direction) -> ShellSection {
        let all = Self.allCases
        let offset = direction == .left ? -1 : 1
        return all[min(max(rawValue + offset, 0), all.count - 1)]
    }
}

struct ShellState {
    var section = ShellSection.home
    var console: GameSystem?
    var barFocus: ShellSection?
    var shelfIndex = 0
    var home = HomeCursor()
    var favorites = FavoritesState()
    var grid: [GameSystem: Int] = [:]
    var gridColumns = 1
    var gallery = GalleryState()
    var search = SearchState()
}

enum FavoritesGrouping: CaseIterable {
    case console
    case genre
    case alphabetical

    var title: String {
        switch self {
        case .console: "Console"
        case .genre: "Genre"
        case .alphabetical: "A–Z"
        }
    }

    var next: FavoritesGrouping {
        let all = Self.allCases
        return all[(all.firstIndex(of: self).map { $0 + 1 } ?? 0) % all.count]
    }
}

struct FavoritesState {
    var grouping = FavoritesGrouping.console
    var cursor = HomeCursor()
}

struct GalleryState {
    var index = 0
    var columns = 1
    var viewer: GalleryViewerModel?
}

struct ConsoleSummary: Equatable {
    let system: GameSystem
    let gameCount: Int
    let inProgress: Int
    let covers: [GameRecord]
}

enum HomeItem: Identifiable, Equatable {
    case game(GameRecord)
    case console(ConsoleSummary)

    var id: String {
        switch self {
        case .game(let game): "game-\(game.id.rawValue)"
        case .console(let summary): "console-\(summary.system.rawValue)"
        }
    }

    var game: GameRecord? {
        if case .game(let game) = self {
            return game
        }
        return nil
    }
}

enum HomeRowKind: Hashable {
    case continuePlaying
    case favorites
    case group(String)
    case pick
    case consoles
    case eighties
    case nineties
    case noughties

    var title: String {
        switch self {
        case .continuePlaying: "Continue playing"
        case .favorites: "Favorites"
        case .group(let title): title
        case .pick: "Tonight's pick"
        case .consoles: "Your consoles"
        case .eighties: "From the 80s"
        case .nineties: "From the 90s"
        case .noughties: "From the 2000s"
        }
    }
}

struct HomeRow: Identifiable {
    let kind: HomeRowKind
    let items: [HomeItem]

    var id: HomeRowKind {
        kind
    }
}

struct HomeSlot {
    let rowIndex: Int
    let column: Int
    let item: HomeItem
}

struct HomeCursor {
    private var rowKind: HomeRowKind?
    private var positions: [HomeRowKind: Int] = [:]

    func column(of kind: HomeRowKind, in rows: [HomeRow]) -> Int {
        guard let row = rows.first(where: { $0.kind == kind }), !row.items.isEmpty else { return 0 }
        return min(positions[kind] ?? 0, row.items.count - 1)
    }

    func slot(in rows: [HomeRow]) -> HomeSlot? {
        guard !rows.isEmpty else { return nil }
        let index = rows.firstIndex { $0.kind == rowKind } ?? 0
        let row = rows[index]
        guard !row.items.isEmpty else { return nil }
        let column = column(of: row.kind, in: rows)
        return HomeSlot(rowIndex: index, column: column, item: row.items[column])
    }

    mutating func move(_ direction: Direction, in rows: [HomeRow]) -> Bool {
        guard let current = slot(in: rows) else { return false }
        let kind = rows[current.rowIndex].kind
        switch direction {
        case .left, .right:
            let count = rows[current.rowIndex].items.count
            let column = min(max(current.column + (direction == .left ? -1 : 1), 0), count - 1)
            guard column != current.column else { return false }
            rowKind = kind
            positions[kind] = column
        case .up, .down:
            let target = current.rowIndex + (direction == .up ? -1 : 1)
            guard rows.indices.contains(target) else { return false }
            rowKind = rows[target].kind
        }
        return true
    }

    mutating func focus(_ id: GameID, in rows: [HomeRow]) {
        for row in rows {
            if let column = row.items.firstIndex(where: { $0.game?.id == id }) {
                rowKind = row.kind
                positions[row.kind] = column
                return
            }
        }
    }

    mutating func reset() {
        rowKind = nil
        positions = [:]
    }
}

enum SearchZone {
    case pad
    case results
}

struct SearchState {
    static let padColumns = 6
    static let keys: [String] = (65...90).compactMap { UnicodeScalar($0).map(String.init) }
        + (0...9).map(String.init)
        + [space, erase]
    static let space = "Space"
    static let erase = "Delete"

    var query = ""
    var zone = SearchZone.pad
    var key = 0
    var result = 0
    var resultColumns = 1

    mutating func apply(_ key: String) {
        switch key {
        case Self.erase:
            if !query.isEmpty {
                query.removeLast()
            }
        case Self.space:
            if !query.isEmpty, query.last != " " {
                query.append(" ")
            }
        default:
            query.append(key)
        }
        result = 0
    }
}

enum GridStep {
    case moved(Int)
    case leftEdge
    case topEdge
    case blocked
}

enum GridMath {
    static func step(_ index: Int, _ direction: Direction, count: Int, columns: Int) -> GridStep {
        let columns = max(1, columns)
        let column = index % columns
        switch direction {
        case .left:
            return column == 0 ? .leftEdge : .moved(index - 1)
        case .right:
            return column == columns - 1 || index + 1 >= count ? .blocked : .moved(index + 1)
        case .up:
            return index < columns ? .topEdge : .moved(index - columns)
        case .down:
            let target = index + columns
            if target < count {
                return .moved(target)
            }
            let lastRowStart = (count - 1) / columns * columns
            return index < lastRowStart ? .moved(count - 1) : .blocked
        }
    }

    static func columns(width: CGFloat, tile: CGFloat, gap: CGFloat) -> Int {
        max(1, Int((width + gap) / (tile + gap)))
    }
}
