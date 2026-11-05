import Foundation

extension AppModel {
    func handleSearch(_ event: NavigationEvent) {
        switch event.action {
        case .text(let text):
            shell.search.apply(text == " " ? SearchState.space : text)
        case .erase:
            shell.search.apply(SearchState.erase)
        case .back:
            if shell.search.query.isEmpty {
                shell.barFocus = .search
            } else {
                shell.search.apply(SearchState.erase)
            }
        case .move(let direction):
            moveSearch(direction)
        case .confirm:
            confirmSearch()
        case .options, .secondary, .pause, .section:
            break
        }
    }

    private func moveSearch(_ direction: Direction) {
        switch shell.search.zone {
        case .pad: movePad(direction)
        case .results: moveResults(direction)
        }
    }

    private func movePad(_ direction: Direction) {
        let keys = SearchState.keys
        switch GridMath.step(shell.search.key, direction, count: keys.count, columns: SearchState.padColumns) {
        case .moved(let target):
            shell.search.key = target
        case .topEdge:
            shell.barFocus = .search
        case .blocked where direction == .right && !searchResults.isEmpty:
            shell.search.zone = .results
        case .leftEdge, .blocked:
            break
        }
    }

    private func moveResults(_ direction: Direction) {
        let count = searchResults.count
        switch GridMath.step(shell.search.result, direction, count: count, columns: shell.search.resultColumns) {
        case .moved(let target): shell.search.result = target
        case .leftEdge: shell.search.zone = .pad
        case .topEdge: shell.barFocus = .search
        case .blocked: break
        }
    }

    private func confirmSearch() {
        switch shell.search.zone {
        case .pad:
            shell.search.apply(SearchState.keys[shell.search.key])
        case .results:
            let results = searchResults
            if results.indices.contains(shell.search.result) {
                show(.gamePanel(results[shell.search.result].id))
            }
        }
    }
}
