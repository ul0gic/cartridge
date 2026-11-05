import SwiftUI

struct RowLabel: View {
    let title: String
    let count: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.n3) {
            Text(title)
                .typeStyle(.headline)
                .foregroundStyle(Palette.textPrimary)
            Text(count)
                .typeStyle(.meta)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(height: Layout.rowLabelHeight, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Row<Content: View>: View {
    let title: String
    let count: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.rowLabelGap) {
            RowLabel(title: title, count: count)
                .padding(.leading, Layout.marginX)
            content
        }
        .frame(height: Layout.rowHeight, alignment: .top)
    }
}

struct TileStrip<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let anchor: Int
    let isAnimated: Bool
    let width: (Item) -> CGFloat
    @ViewBuilder let tile: (Int, Item) -> Content

    var body: some View {
        GeometryReader { proxy in
            let offsets = Self.offsets(of: items.map(width))
            let first = max(0, min(anchor, items.count - 1) - Layout.tilesBeforeHighlight)
            let visible = Int((proxy.size.width / (Layout.tileHeight * 0.72)).rounded(.up))
            let lower = max(0, first - visible)
            let upper = min(items.count, first + visible * 2)
            let window = Array(items.enumerated()).filter { (lower..<upper).contains($0.offset) }
            HStack(spacing: Layout.tileGap) {
                ForEach(window, id: \.element.id) { index, item in
                    tile(index, item)
                }
            }
            .padding(.leading, Layout.marginX)
            .offset(x: items.isEmpty ? 0 : offsets[lower] - offsets[first])
            .animation(isAnimated ? Motion.easeOut(Motion.scroll) : nil, value: first)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Layout.tileHeight)
    }

    private static func offsets(of widths: [CGFloat]) -> [CGFloat] {
        var offsets: [CGFloat] = []
        var x: CGFloat = 0
        for width in widths {
            offsets.append(x)
            x += width + Layout.tileGap
        }
        return offsets
    }
}
