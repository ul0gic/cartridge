import SwiftUI

struct HubHintsRow: View {
    let hints: [Hint]
    let glyphs: HintGlyphs?
    let showsRewind: Bool
    let counter: String?

    var body: some View {
        HStack(spacing: Space.n6) {
            if showsRewind, let back = hints.last {
                HintsRow(hints: Array(hints.dropLast()), glyphs: glyphs)
                RewindHint()
                HintsRow(hints: [back], glyphs: glyphs)
            } else {
                HintsRow(hints: hints, glyphs: glyphs)
            }
            Spacer(minLength: 0)
            if let counter {
                Text(counter)
                    .typeStyle(TypeStyle.hint.digits)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(minHeight: Layout.keycapHeight)
    }
}

private struct RewindHint: View {
    var body: some View {
        HStack(spacing: Space.n2) {
            GlyphLabel(symbol: "l2.button.roundedtop.horizontal", size: Layout.glyphHint)
            Text("Hold to rewind")
                .typeStyle(.hint)
                .foregroundStyle(Palette.textSecondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("L2 button: Hold to rewind")
    }
}

struct HubHeader: View {
    let game: GameRecord
    let title: String
    let subtitle: String
    let art: TileArt

    var body: some View {
        HStack(alignment: .center, spacing: Space.n4) {
            ArtFace(title: game.title, system: game.system, art: art, style: .thumb)
                .frame(width: Layout.thumbHeight * game.system.tileAspect, height: Layout.thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.n1) {
                Text(title)
                    .typeStyle(.titleM)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .typeStyle(.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Layout.thumbHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ColumnScroll<Content: View>: View {
    var scrollTarget: AnyHashable?
    @ViewBuilder let content: Content

    @State private var contentHeight: CGFloat = 0
    @State private var hasMoreBelow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(Layout.focusBleed)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
            } action: { _, more in
                hasMoreBelow = more
            }
            .frame(maxHeight: contentHeight > 0 ? contentHeight : .infinity)
            .mask { fade }
            .padding(-Layout.focusBleed)
            .onChange(of: scrollTarget) {
                guard let scrollTarget else { return }
                withAnimation(reduceMotion ? nil : Motion.easeOut(Motion.scroll)) {
                    proxy.scrollTo(scrollTarget, anchor: .center)
                }
            }
        }
    }

    private var fade: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, hasMoreBelow ? .clear : .black], startPoint: .top, endPoint: .bottom)
                .frame(height: HubStyle.fadeHeight)
        }
    }
}

struct HubColumn<Content: View>: View {
    let game: GameRecord
    let title: String
    let subtitle: String
    let art: TileArt
    let hints: [Hint]
    let glyphs: HintGlyphs?
    let showsRewind: Bool
    let counter: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubHeader(game: game, title: title, subtitle: subtitle, art: art)
                .padding(.bottom, Space.n5)
            content
            HubHintsRow(hints: hints, glyphs: glyphs, showsRewind: showsRewind, counter: counter)
                .padding(.top, Space.n5)
        }
        .padding(.top, Space.n6)
        .padding(.horizontal, Space.n6)
        .padding(.bottom, Space.n5)
        .frame(width: HubStyle.columnWidth)
        .hubPlate(radius: Radius.sheet)
        .shadow(color: Palette.shadowArt, radius: 35, x: 0, y: 30)
    }
}
