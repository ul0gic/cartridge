import SwiftUI

struct LibraryScreen: View {
    let model: AppModel

    var body: some View {
        switch model.route == .scanning ? .browse : model.homeState {
        case .browse where model.route == .scanning:
            BrowseLayout(model: model)
        case .browse:
            ShellScreen(model: model)
        case .empty(let folder):
            EmptyLibraryScreen(model: model, folder: folder)
        case .missing(let folder):
            MissingFolderScreen(model: model, folder: folder)
        }
    }
}

struct BrowseLayout: View {
    let model: AppModel

    var body: some View {
        content.onAppear { model.libraryDidAppear() }
    }

    @ViewBuilder private var content: some View {
        let rows = model.rows
        let slot = model.cursor.slot(in: rows)
        let scan = model.scan
        let isScanning = model.route == .scanning
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: Self.hints,
            counter: slot.map { "\($0.column + 1) of \(rows[$0.rowIndex].games.count)" },
            backdrop: { LibraryBackdrop(model: model, game: slot?.game) },
            content: {
                VStack(spacing: 0) {
                    if let title = model.crashedGameTitle {
                        CrashBand(gameTitle: title, glyphs: model.chrome.glyphs)
                            .padding(.bottom, Space.n3)
                    }
                    HStack(alignment: .bottom, spacing: Space.n7) {
                        heroColumn(isScanning: isScanning, slot: slot, scan: scan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RowRail(
                            entries: LibraryRows.railEntries(rows: rows, scan: isScanning ? scan : nil, isEmpty: false),
                            currentIndex: railIndex(rows: rows, slot: slot, isScanning: isScanning)
                        )
                    }
                    .padding(.horizontal, Layout.marginX)
                    .frame(height: Layout.heroHeight)
                    RowsRegion(model: model, rows: rows, activeRow: slot?.rowIndex ?? 0, isScanning: isScanning)
                        .padding(.top, Space.n4)
                }
                .padding(.top, model.chrome.safeTop + Space.n2 + Layout.topbarHeight + Space.n2)
                .padding(.bottom, Layout.hintbarHeight)
                .animation(Motion.easeOut(Motion.band), value: model.crashedGameTitle)
            }
        )
    }

    private static let hints = [
        Hint(kind: .game, label: "Game"),
        Hint(kind: .row, label: "Row"),
        Hint(kind: .confirm, label: "Open"),
        Hint(kind: .options, label: "Settings"),
    ]

    private func heroColumn(isScanning: Bool, slot: LibrarySlot?, scan: ScanProgress?) -> some View {
        Group {
            if isScanning, let scan {
                ScanningHero(scan: scan)
            } else if let slot {
                Hero(
                    system: slot.game.system.displayName,
                    title: slot.game.title,
                    metadata: model.metadata(for: slot.game),
                    state: model.resumeDate(for: slot.game).map { .resume(DisplayDate.text($0)) } ?? .unplayed
                )
            }
        }
        .transition(.opacity)
        .animation(Motion.easeInOut(Motion.handover), value: isScanning)
    }

    private func railIndex(rows: [LibraryRow], slot: LibrarySlot?, isScanning: Bool) -> Int? {
        guard let slot else { return nil }
        let key = rows[slot.rowIndex].key
        guard isScanning else { return slot.rowIndex }
        guard case .system(let system) = key else { return nil }
        return GameSystem.allCases.firstIndex(of: system)
    }
}

private struct LibraryBackdrop: View {
    let model: AppModel
    let game: GameRecord?

    @State private var colors = AmbientColors.brand
    @State private var source = BackdropSource.collage

    var body: some View {
        ZStack {
            CinematicBackdrop(source: source)
            AmbientBackdrop(colors: colors, layout: .cinematic, drawsBase: false, intensity: 0.3)
        }
        .task(id: BackdropKey(id: game?.id, art: game?.artStatus)) {
            guard let game else { return }
            colors = await model.ambientColors(for: game)
        }
        .task(id: game?.id) {
            guard let game else { return }
            source = await model.backdrop(for: game)
        }
    }
}

private struct BackdropKey: Equatable {
    let id: GameID?
    let art: ArtStatus?
}

private struct RowsRegion: View {
    let model: AppModel
    let rows: [LibraryRow]
    let activeRow: Int
    let isScanning: Bool

    var body: some View {
        GeometryReader { proxy in
            let visible = Int((proxy.size.height / Layout.rowPitch).rounded(.up)) + 1
            let lower = max(0, activeRow - 1)
            let upper = min(rows.count, activeRow + visible + 1)
            VStack(alignment: .leading, spacing: Layout.rowGap) {
                ForEach(rows[lower..<upper]) { row in
                    GameRow(
                        model: model,
                        rows: rows,
                        row: row,
                        isActive: rows[activeRow].key == row.key,
                        isScanning: isScanning
                    )
                }
            }
            .offset(y: CGFloat(lower - activeRow) * Layout.rowPitch)
            .animation(model.animatesScroll ? Motion.easeOut(Motion.scroll) : nil, value: activeRow)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .clipped()
    }
}

private struct GameRow: View {
    let model: AppModel
    let rows: [LibraryRow]
    let row: LibraryRow
    let isActive: Bool
    let isScanning: Bool

    var body: some View {
        let position = model.cursor.position(of: row.key, in: rows)
        Row(title: row.key.title, count: countText) {
            TileStrip(
                items: row.games,
                anchor: position,
                isAnimated: model.animatesScroll,
                width: { Layout.tileWidth(for: $0.system.tileAspect) },
                tile: { index, game in
                    GameTile(model: model, game: game, isHighlighted: isActive && index == position)
                }
            )
        }
    }

    private var countText: String {
        isScanning ? "\(row.games.count.formatted()) so far" : LibraryRows.gameCount(row.games.count)
    }
}

struct GameTile: View {
    let model: AppModel
    let game: GameRecord
    let isHighlighted: Bool

    @State private var art = TileArt.loading

    var body: some View {
        Tile(
            title: game.title,
            system: game.system,
            art: art,
            identifyingFileName: nil,
            isHighlighted: isHighlighted
        )
        .task(id: game.artStatus) {
            art = await model.tileArt(for: game)
        }
    }
}
