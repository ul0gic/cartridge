import Foundation
import SwiftUI

extension AppModel {
    private static let otherGenre = "Other"

    var favoriteRows: [HomeRow] {
        let games = dependencies.library.favorites().sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let groups: [(title: String, games: [GameRecord])] = switch shell.favorites.grouping {
        case .console:
            GameSystem.allCases.sorted { $0.libraryOrder < $1.libraryOrder }
                .map { system in (system.displayName, games.filter { $0.system == system }) }
        case .genre:
            genreGroups(of: games)
        case .alphabetical:
            [("All favorites", games)]
        }
        return groups.filter { !$0.games.isEmpty }.map {
            HomeRow(kind: .group($0.title), items: $0.games.map(HomeItem.game))
        }
    }

    var canRemoveFromContinue: Bool {
        guard shell.section == .home, shell.barFocus == nil, route == .library else { return false }
        let rows = homeRows
        guard let slot = shell.home.slot(in: rows) else { return false }
        return rows[slot.rowIndex].kind == .continuePlaying
    }

    func isFavorite(_ game: GameRecord) -> Bool {
        dependencies.library.isFavorite(game.id)
    }

    func toggleFavorite(_ game: GameRecord) {
        let library = dependencies.library
        let adding = !library.isFavorite(game.id)
        library.setFavorite(adding, for: game.id)
        UISound.play(.select)
        dependencies.controller.feedback(.confirm)
        AccessibilityNotification.Announcement(adding ? "Added to Favorites" : "Removed from Favorites").post()
    }

    func removeFromContinue(_ game: GameRecord) {
        guard var record = playRecord(for: game) else { return }
        record.continueHiddenAt = .now
        let library = dependencies.library
        Task { await library.recordPlay(record, for: game.id) }
        UISound.play(.back)
        dependencies.controller.feedback(.tick)
        AccessibilityNotification.Announcement("Removed from Continue playing").post()
    }

    func handleFavorites(_ event: NavigationEvent) {
        let rows = favoriteRows
        if event.action == .secondary {
            cycleFavoritesGrouping(in: rows)
            return
        }
        guard !rows.isEmpty else {
            if event.action == .back || event.action == .move(.up) {
                shell.barFocus = .favorites
            }
            return
        }
        handleRows(event, rows: rows, cursor: \.favorites.cursor, section: .favorites)
    }

    private func cycleFavoritesGrouping(in rows: [HomeRow]) {
        guard !rows.isEmpty else { return }
        let focused = shell.favorites.cursor.slot(in: rows)?.item.game?.id
        shell.favorites.grouping = shell.favorites.grouping.next
        UISound.play(.tab)
        dependencies.controller.feedback(.tick)
        guard let focused else { return }
        shell.favorites.cursor.reset()
        shell.favorites.cursor.focus(focused, in: favoriteRows)
    }

    private func genreGroups(of games: [GameRecord]) -> [(title: String, games: [GameRecord])] {
        let byGenre = Dictionary(grouping: games) { dependencies.library.metadata(for: $0)?.genre ?? Self.otherGenre }
        let named = byGenre.keys.filter { $0 != Self.otherGenre }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return (named + [Self.otherGenre]).map { ($0, byGenre[$0] ?? []) }
    }
}
