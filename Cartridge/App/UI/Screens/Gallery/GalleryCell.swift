import SwiftUI

enum GalleryMetrics {
    static let cellWidth: CGFloat = 288
    static let imageHeight: CGFloat = cellWidth * 3 / 4
    static let textHeight: CGFloat = 48
    static let cellHeight = imageHeight + Space.n4 + textHeight
    static let pitch = cellHeight + Layout.gridGap
}

struct GalleryCell: View {
    let item: CaptureItem
    let url: URL
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isVoiceOverFocused: Bool
    @State private var phase: ThumbnailPhase

    init(item: CaptureItem, url: URL, isHighlighted: Bool) {
        self.item = item
        self.url = url
        self.isHighlighted = isHighlighted
        _phase = State(initialValue: GalleryThumbnails.cached(url).map { .image($0.image) } ?? .loading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            picture
                .frame(width: GalleryMetrics.cellWidth, height: GalleryMetrics.imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile))
                .overlay(alignment: .bottomTrailing) { badge }
                .focusRing(isHighlighted, radius: Radius.tile)
                .shadow(
                    color: isHighlighted ? Palette.shadowLift : .clear,
                    radius: Layout.shadowLiftBlur / 2,
                    x: 0,
                    y: Layout.shadowLiftOffset
                )
                .scaleEffect(isHighlighted && !reduceMotion ? Layout.focusScale : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.gameTitle)
                    .typeStyle(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.cellLine)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.top, isHighlighted ? Space.n4 : Space.n3)
            .frame(width: GalleryMetrics.cellWidth, height: GalleryMetrics.textHeight + Space.n4, alignment: .top)
        }
        .frame(width: GalleryMetrics.cellWidth, height: GalleryMetrics.cellHeight, alignment: .top)
        .animation(Motion.easeOut(Motion.focus), value: isHighlighted)
        .zIndex(isHighlighted ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the \(item.noun)")
        .accessibilityAddTraits(.isButton)
        .accessibilityFocused($isVoiceOverFocused)
        .onChange(of: isHighlighted) {
            if isHighlighted {
                isVoiceOverFocused = true
            }
        }
        .task(id: item.id) {
            let thumbnail = await GalleryThumbnails.load(url, kind: item.kind)
            phase = thumbnail.map { .image($0.image) } ?? .missing
        }
    }

    @ViewBuilder private var picture: some View {
        switch phase {
        case .loading:
            LoadingFace { EmptyView() }
        case .missing:
            LoadingFace {
                VStack(spacing: Space.n2) {
                    GlyphLabel(
                        symbol: "exclamationmark.triangle.fill",
                        size: Layout.glyphStatus,
                        color: Palette.warning
                    )
                    Text("File not found")
                        .typeStyle(.meta)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        case .image(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        }
    }

    @ViewBuilder private var badge: some View {
        if case .image = phase, let label = badgeLabel {
            HStack(spacing: Space.n1) {
                if item.kind == .clip {
                    GlyphLabel(symbol: "play.fill", size: TypeStyle.caption.size)
                }
                Text(label)
            }
            .typeStyle(TypeStyle.caption.digits)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.n2)
            .padding(.vertical, Space.half)
            .background(HubStyle.materialPlay, in: Capsule())
            .padding(Space.n2)
        }
    }

    private var badgeLabel: String? {
        switch item.kind {
        case .screenshot: nil
        case .clip: item.durationText
        case .gif: "GIF"
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.gameTitle, item.kindName.lowercased(), DisplayDate.text(item.capturedAt)]
        if item.kind == .clip, let durationText = item.durationText {
            parts.append(durationText)
        }
        if case .missing = phase {
            parts.append("file not found")
        }
        return parts.joined(separator: ", ")
    }
}

private enum ThumbnailPhase {
    case loading
    case missing
    case image(CGImage)
}

struct GalleryGrid: View {
    let store: GalleryStore
    let focused: Int?
    let animatesScroll: Bool
    let onColumns: (Int) -> Void

    var body: some View {
        let items = store.items
        let focusedID = focused.flatMap { items.indices.contains($0) ? items[$0].id : nil }
        GeometryReader { proxy in
            let columns = GridMath.columns(
                width: proxy.size.width,
                tile: GalleryMetrics.cellWidth,
                gap: Layout.tileGap
            )
            let rowCount = (items.count + columns - 1) / columns
            let focusRow = (focused ?? 0) / columns
            let visible = Int((proxy.size.height / GalleryMetrics.pitch).rounded(.up)) + 1
            let top = max(0, min(focusRow - 1, rowCount - visible + 1))
            let lower = max(0, top - 1)
            let upper = min(rowCount, top + visible + 1)
            VStack(alignment: .leading, spacing: Layout.gridGap) {
                ForEach(lower..<max(lower, upper), id: \.self) { row in
                    HStack(spacing: Layout.tileGap) {
                        ForEach(items[row * columns..<min(items.count, (row + 1) * columns)]) { item in
                            GalleryCell(item: item, url: store.url(of: item), isHighlighted: item.id == focusedID)
                        }
                    }
                }
            }
            .offset(y: CGFloat(lower - top) * GalleryMetrics.pitch)
            .animation(animatesScroll ? Motion.easeOut(Motion.scroll) : nil, value: top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { onColumns(columns) }
            .onChange(of: columns) { onColumns(columns) }
        }
        .padding(.top, Space.n3)
        .mask { Rectangle().padding(.horizontal, -Layout.focusBleed) }
    }
}
