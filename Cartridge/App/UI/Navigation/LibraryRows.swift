enum LibraryRows {
    @MainActor
    static func rows(from library: any LibraryStoring) -> [LibraryRow] {
        var rows: [LibraryRow] = []
        let resuming = library.continuePlaying()
        if !resuming.isEmpty {
            rows.append(LibraryRow(key: .continuePlaying, games: resuming))
        }
        for system in GameSystem.allCases.sorted(by: { $0.libraryOrder < $1.libraryOrder }) {
            let games = library.games(in: system)
            if !games.isEmpty {
                rows.append(LibraryRow(key: .system(system), games: games))
            }
        }
        return rows
    }

    static func railEntries(rows: [LibraryRow], scan: ScanProgress?, isEmpty: Bool) -> [RailEntry] {
        if isEmpty {
            return GameSystem.allCases.map {
                RailEntry(name: $0.displayName, value: "None", spokenValue: "no games", isNone: true)
            }
        }
        if let scan, !scan.isFinished {
            return GameSystem.allCases.map { system in
                let count = scan.perSystem[system] ?? 0
                return count == 0
                    ? RailEntry(name: system.displayName, value: "None yet", spokenValue: "none yet", isNone: true)
                    : RailEntry(name: system.displayName, value: count.formatted(), spokenValue: gameCount(count))
            }
        }
        return rows.map {
            RailEntry(name: $0.key.title, value: $0.games.count.formatted(), spokenValue: gameCount($0.games.count))
        }
    }

    static func gameCount(_ count: Int) -> String {
        count == 1 ? "1 game" : "\(count.formatted()) games"
    }
}
