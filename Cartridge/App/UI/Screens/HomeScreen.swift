import SwiftUI

struct HomeScreen: View {
    let model: AppModel
    var page = ShellSection.home

    private var isFavorites: Bool {
        page == .favorites
    }

    private var hints: [Hint] {
        var hints = [Hint(kind: .move, label: "Move"), Hint(kind: .confirm, label: "Open")]
        if isFavorites {
            hints.append(Hint(kind: .secondary, label: "Group: \(model.shell.favorites.grouping.title)"))
        } else if model.canRemoveFromContinue {
            hints.append(Hint(kind: .secondary, label: "Remove"))
        }
        return hints + [Hint(kind: .options, label: "Settings")]
    }

    var body: some View {
        let rows = isFavorites ? model.favoriteRows : model.homeRows
        let cursor = isFavorites ? model.shell.favorites.cursor : model.shell.home
        let slot = cursor.slot(in: rows)
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: model.shellHints(hints),
            bar: model.shellBar,
            console: framedSystem(slot?.item),
            backdrop: {
                ZStack {
                    if let system = framedSystem(slot?.item) {
                        ConsoleFrame(
                            system: system,
                            artTop: model.contentTop - Space.n4,
                            artHeight: Layout.heroHeight + Space.n4
                        )
                        .transition(.opacity)
                    } else {
                        GameBackdrop(model: model, game: backdropGame(slot?.item))
                            .transition(.opacity)
                    }
                }
                .animation(Motion.easeInOut(Motion.ambient), value: framedSystem(slot?.item) == nil)
            },
            content: {
                if isFavorites, rows.isEmpty {
                    EmptyFavorites(topInset: model.contentTop)
                } else {
                    rowsContent(rows: rows, cursor: cursor, slot: slot)
                }
            }
        )
    }

    private func rowsContent(rows: [HomeRow], cursor: HomeCursor, slot: HomeSlot?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = model.crashedGameTitle {
                CrashBand(gameTitle: title, glyphs: model.chrome.glyphs)
                    .padding(.bottom, Space.n3)
            }
            HomeHero(model: model, item: slot?.item)
                .padding(.horizontal, Layout.marginX)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                .frame(height: Layout.heroHeight, alignment: .bottomLeading)
            HomeRowsRegion(
                model: model,
                rows: rows,
                cursor: cursor,
                activeRow: slot?.rowIndex ?? 0,
                isFocused: model.shell.barFocus == nil,
                system: framedSystem(slot?.item)
            )
            .padding(.top, Space.n5)
        }
        .padding(.top, model.contentTop)
        .padding(.bottom, Layout.hintbarHeight)
        .animation(Motion.easeOut(Motion.band), value: model.crashedGameTitle)
    }

    private func framedSystem(_ item: HomeItem?) -> GameSystem? {
        if case .console(let summary) = item {
            return summary.system
        }
        return nil
    }

    private func backdropGame(_ item: HomeItem?) -> GameRecord? {
        switch item {
        case .game(let game): game
        case .console(let summary): summary.covers.first
        case nil: nil
        }
    }
}

private struct HomeHero: View {
    let model: AppModel
    let item: HomeItem?

    var body: some View {
        switch item {
        case .game(let game):
            GameHero(model: model, game: game)
        case .console(let summary):
            VStack(alignment: .leading, spacing: 0) {
                SystemBadge(name: "\(summary.system.maker) · \(String(summary.system.launchYear))")
                    .padding(.bottom, Space.n4)
                Text(summary.system.displayName)
                    .typeStyle(.titleXL)
                    .foregroundStyle(Palette.textPrimary)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 6)
                HStack(spacing: Space.n5) {
                    Text(LibraryRows.gameCount(summary.gameCount))
                        .fontWeight(.bold)
                        .foregroundStyle(Palette.textPrimary)
                    if summary.inProgress > 0 {
                        Text("\(summary.inProgress) in progress")
                    }
                }
                .typeStyle(.lede)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, Space.n4)
            }
        case nil:
            EmptyView()
        }
    }
}

private struct HomeRowsRegion: View {
    let model: AppModel
    let rows: [HomeRow]
    let cursor: HomeCursor
    let activeRow: Int
    let isFocused: Bool
    let system: GameSystem?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let visible = Int((proxy.size.height / Layout.rowPitch).rounded(.up)) + 1
            let lower = max(0, activeRow - 1)
            let upper = min(rows.count, activeRow + visible + 1)
            VStack(alignment: .leading, spacing: Layout.rowGap) {
                ForEach(Array(rows[lower..<upper].enumerated()), id: \.element.id) { offset, row in
                    HomeRowView(
                        model: model,
                        row: row,
                        position: cursor.column(of: row.kind, in: rows),
                        isActive: isFocused && rows[activeRow].kind == row.kind
                    )
                    .padding(
                        .top,
                        system != nil && lower + offset == activeRow + 1
                            ? Layout.consoleFrameRowGap - Layout.rowGap
                            : 0
                    )
                }
            }
            .animation(reduceMotion ? nil : Motion.easeOut(Motion.scroll), value: rows.map(\.id))
            .offset(y: CGFloat(lower - activeRow) * Layout.rowPitch)
            .animation(model.animatesScroll ? Motion.easeOut(Motion.scroll) : nil, value: activeRow)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .mask {
                if system != nil {
                    HomeRowsMask(panelTop: panelTop)
                } else {
                    Rectangle()
                }
            }
            .background(alignment: .top) {
                if let system {
                    ConsoleWell(system: system)
                        .padding(.horizontal, Layout.consoleFrameInset)
                        .padding(.top, panelTop)
                        .padding(.bottom, Space.n3)
                        .transition(.opacity)
                }
            }
            .animation(Motion.easeInOut(Motion.ambient), value: system)
        }
        .clipped()
    }

    private var panelTop: CGFloat {
        Layout.rowHeight + Layout.consoleFrameRowGap - Space.n3
    }
}

private struct HomeRowsMask: Shape {
    let panelTop: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(panelTop, rect.height)))
        path.addPath(ConsoleWellMask(topInset: panelTop, bottomInset: Space.n3).path(in: rect))
        return path
    }
}

private struct HomeRowView: View {
    let model: AppModel
    let row: HomeRow
    let position: Int
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Row(title: row.kind.title, count: countText) {
            if row.kind == .consoles {
                HomeConsoleStrip(model: model, items: row.items, position: position, isActive: isActive)
            } else {
                TileStrip(
                    items: row.items,
                    anchor: position,
                    isAnimated: model.animatesScroll,
                    width: width(for:)
                ) { index, item in
                    itemView(item, isHighlighted: isActive && index == position)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                }
                .animation(reduceMotion ? nil : Motion.easeOut(Motion.scroll), value: row.items.map(\.id))
            }
        }
    }

    private var countText: String {
        switch row.kind {
        case .pick: ""
        case .consoles: row.items.count == 1 ? "1 console" : "\(row.items.count) consoles"
        case .continuePlaying, .favorites, .group, .eighties, .nineties, .noughties:
            LibraryRows.gameCount(row.items.count)
        }
    }

    private func width(for item: HomeItem) -> CGFloat {
        switch (row.kind, item) {
        case (.continuePlaying, _), (_, .console): Layout.momentWidth
        case (.pick, _): Layout.pickWidth
        case (_, .game(let game)): Layout.tileWidth(for: game.system.tileAspect)
        }
    }

    @ViewBuilder
    private func itemView(_ item: HomeItem, isHighlighted: Bool) -> some View {
        switch (row.kind, item) {
        case (_, .console(let summary)):
            ConsoleCard(model: model, summary: summary, isHighlighted: isHighlighted)
        case (.continuePlaying, .game(let game)):
            MomentCard(model: model, game: game, isHighlighted: isHighlighted)
        case (.pick, .game(let game)):
            PickCard(model: model, game: game, isHighlighted: isHighlighted)
        case (_, .game(let game)):
            GameTile(model: model, game: game, isHighlighted: isHighlighted)
        }
    }
}

private struct HomeConsoleStrip: View {
    let model: AppModel
    let items: [HomeItem]
    let position: Int
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = CGFloat(max(1, items.count))
            let available = proxy.size.width - Layout.marginX * 2 - Space.n5 * (count - 1)
            let width = min(Layout.momentWidth, max(0, available / count))
            HStack(spacing: Space.n5) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if case .console(let summary) = item {
                        ConsoleCard(
                            model: model,
                            summary: summary,
                            isHighlighted: isActive && index == position,
                            width: width
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: Layout.tileHeight)
        }
        .frame(height: Layout.tileHeight)
    }
}

private struct PickCard: View {
    let model: AppModel
    let game: GameRecord
    let isHighlighted: Bool

    @State private var scene: BackdropSource?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SceneArt(source: scene)
                .frame(width: Layout.pickWidth, height: Layout.tileHeight)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: Space.half) {
                Text(game.title)
                    .typeStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                Text(MetadataText.line(model.metadata(for: game)) ?? game.system.displayName)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: Layout.pickWidth * 0.6, alignment: .leading)
            .padding(Space.n4)
        }
        .frame(width: Layout.pickWidth, height: Layout.tileHeight)
        .focusLift(isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tonight's pick, \(game.title), \(game.system.displayName)")
        .accessibilityAddTraits(.isButton)
        .task(id: game.id) { scene = await model.backdrop(for: game) }
    }
}
