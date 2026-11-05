import SwiftUI

struct SearchScreen: View {
    let model: AppModel

    var body: some View {
        let search = model.shell.search
        let results = model.searchResults
        let isFocused = model.shell.barFocus == nil
        let focusedGame = search.zone == .results && results.indices.contains(search.result)
            ? results[search.result]
            : results.first
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: model.shellHints([
                Hint(kind: .move, label: "Move"),
                Hint(kind: .confirm, label: search.zone == .pad ? "Type" : "Open"),
                Hint(kind: .back, label: "Delete"),
            ]),
            counter: results.isEmpty ? nil : LibraryRows.gameCount(results.count),
            bar: model.shellBar,
            backdrop: { GameBackdrop(model: model, game: focusedGame, style: .detail) },
            content: {
                HStack(alignment: .top, spacing: Space.n8) {
                    VStack(alignment: .leading, spacing: Space.n5) {
                        QueryLine(query: search.query)
                        LetterPad(focused: isFocused && search.zone == .pad ? search.key : nil)
                    }
                    .frame(width: Layout.padWidth, alignment: .leading)
                    if results.isEmpty {
                        SearchPrompt(hasQuery: !search.query.isEmpty)
                    } else {
                        GameGrid(
                            model: model,
                            games: results,
                            focused: isFocused && search.zone == .results ? search.result : nil,
                            cellWidth: Layout.searchCellWidth
                        ) { model.shell.search.resultColumns = $0 }
                    }
                }
                .padding(.horizontal, Layout.marginX)
                .padding(.top, model.contentTop + Space.n5)
                .padding(.bottom, Layout.hintbarHeight)
            }
        )
    }
}

private struct QueryLine: View {
    let query: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.n1) {
            Text(query.isEmpty ? "Search" : query)
                .typeStyle(.titleL)
                .foregroundStyle(query.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
            Capsule()
                .fill(Palette.focusRing)
                .frame(width: Layout.caretWidth, height: Layout.caretHeight)
                .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.15]) { caret, opacity in
                    caret.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.55)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(query.isEmpty ? "Search, empty" : "Search, \(query)")
    }
}

private struct LetterPad: View {
    let focused: Int?

    var body: some View {
        let keys = SearchState.keys
        let columns = SearchState.padColumns
        VStack(alignment: .leading, spacing: Space.n2) {
            ForEach(0..<(keys.count + columns - 1) / columns, id: \.self) { row in
                HStack(spacing: Space.n2) {
                    ForEach(row * columns..<min(keys.count, (row + 1) * columns), id: \.self) { index in
                        PadKey(label: keys[index], isFocused: index == focused)
                    }
                }
            }
        }
        .padding(Space.n4)
        .glassSurface(in: RoundedRectangle(cornerRadius: Radius.art))
    }
}

private struct PadKey: View {
    let label: String
    let isFocused: Bool

    var body: some View {
        let isWide = label.count > 1
        Group {
            if label == SearchState.erase {
                Image(systemName: "delete.left")
            } else if label == SearchState.space {
                Text("Space")
            } else {
                Text(label)
            }
        }
        .typeStyle(isWide ? .meta : .headline)
        .fontWeight(.bold)
        .foregroundStyle(isFocused ? Palette.actionText : Palette.textPrimary)
        .frame(width: isWide ? Layout.padKey * 2.5 : Layout.padKey, height: Layout.padKey)
        .background {
            RoundedRectangle(cornerRadius: Radius.keycap)
                .fill(isFocused ? Palette.actionFill : Palette.textPrimary.opacity(0.08))
                .shadow(color: isFocused ? Palette.actionFill.opacity(0.4) : .clear, radius: 14)
        }
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(Motion.easeOut(Motion.focus), value: isFocused)
        .accessibilityLabel(label)
    }
}

private struct SearchPrompt: View {
    let hasQuery: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.n3) {
            Text(hasQuery ? "No games match" : "Find a game")
                .typeStyle(.titleM)
                .foregroundStyle(Palette.textPrimary)
            Text(hasQuery
                ? "Try fewer letters, or the start of another word in the title."
                : "Type the start of any word in a title. Results come from every console.")
                .typeStyle(.lede)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: Layout.measure, alignment: .leading)
        }
        .padding(.top, Space.n7)
    }
}
