enum LibraryRowKey: Hashable {
    case continuePlaying
    case system(GameSystem)

    var rawKey: String {
        switch self {
        case .continuePlaying: "continue"
        case .system(let system): system.rawValue
        }
    }

    var title: String {
        switch self {
        case .continuePlaying: "Continue playing"
        case .system(let system): system.displayName
        }
    }

    init?(rawKey: String) {
        if rawKey == Self.continuePlaying.rawKey {
            self = .continuePlaying
        } else if let system = GameSystem(rawValue: rawKey) {
            self = .system(system)
        } else {
            return nil
        }
    }
}

struct LibraryRow: Identifiable {
    let key: LibraryRowKey
    let games: [GameRecord]

    var id: LibraryRowKey {
        key
    }
}

struct LibrarySlot {
    let rowIndex: Int
    let column: Int
    let game: GameRecord
}

struct LibraryCursor {
    private var rowKey: LibraryRowKey?
    private var positions: [LibraryRowKey: Int] = [:]

    func position(of key: LibraryRowKey, in rows: [LibraryRow]) -> Int {
        guard let row = rows.first(where: { $0.key == key }), !row.games.isEmpty else { return 0 }
        return min(positions[key] ?? 0, row.games.count - 1)
    }

    func slot(in rows: [LibraryRow]) -> LibrarySlot? {
        guard !rows.isEmpty else { return nil }
        let index = rows.firstIndex { $0.key == rowKey } ?? 0
        let row = rows[index]
        guard !row.games.isEmpty else { return nil }
        let column = position(of: row.key, in: rows)
        return LibrarySlot(rowIndex: index, column: column, game: row.games[column])
    }

    @discardableResult
    mutating func move(_ direction: Direction, in rows: [LibraryRow]) -> Bool {
        guard let current = slot(in: rows) else { return false }
        let key = rows[current.rowIndex].key
        switch direction {
        case .left, .right:
            let count = rows[current.rowIndex].games.count
            let column = min(max(current.column + (direction == .left ? -1 : 1), 0), count - 1)
            guard column != current.column else { return false }
            rowKey = key
            positions[key] = column
        case .up, .down:
            let target = min(max(current.rowIndex + (direction == .up ? -1 : 1), 0), rows.count - 1)
            guard target != current.rowIndex else { return false }
            rowKey = rows[target].key
        }
        return true
    }

    mutating func restore(_ selection: LibrarySelection, in rows: [LibraryRow]) {
        guard let key = LibraryRowKey(rawKey: selection.rowKey),
              let row = rows.first(where: { $0.key == key }),
              let column = row.games.firstIndex(where: { $0.id == selection.gameID })
        else { return }
        rowKey = key
        positions[key] = column
    }

    mutating func focus(_ game: GameRecord, in rows: [LibraryRow], preferringContinue: Bool) {
        let candidates = preferringContinue ? rows : rows.filter { $0.key != .continuePlaying }
        for row in candidates {
            if let column = row.games.firstIndex(where: { $0.id == game.id }) {
                rowKey = row.key
                positions[row.key] = column
                return
            }
        }
    }
}
