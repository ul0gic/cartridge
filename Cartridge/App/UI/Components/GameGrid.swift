import SwiftUI

struct GameGrid: View {
    let model: AppModel
    let games: [GameRecord]
    let focused: Int?
    let cellWidth: CGFloat
    let onColumns: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let columns = GridMath.columns(width: proxy.size.width, tile: cellWidth, gap: Layout.tileGap)
            let pitch = Layout.tileHeight + Layout.gridGap
            let rowCount = (games.count + columns - 1) / columns
            let focusRow = (focused ?? 0) / columns
            let visible = Int((proxy.size.height / pitch).rounded(.up)) + 1
            let top = max(0, min(focusRow - 1, rowCount - visible + 1))
            let lower = max(0, top - 1)
            let upper = min(rowCount, top + visible + 1)
            VStack(alignment: .leading, spacing: Layout.gridGap) {
                ForEach(lower..<max(lower, upper), id: \.self) { row in
                    HStack(spacing: Layout.tileGap) {
                        ForEach(row * columns..<min(games.count, (row + 1) * columns), id: \.self) { index in
                            GameTile(model: model, game: games[index], isHighlighted: index == focused)
                                .frame(width: cellWidth)
                        }
                    }
                }
            }
            .offset(y: CGFloat(lower - top) * pitch)
            .animation(model.animatesScroll ? Motion.easeOut(Motion.scroll) : nil, value: top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { onColumns(columns) }
            .onChange(of: columns) { onColumns(columns) }
        }
        .padding(.top, Space.n3)
        .mask { Rectangle().padding(.horizontal, -Layout.focusBleed) }
    }
}
