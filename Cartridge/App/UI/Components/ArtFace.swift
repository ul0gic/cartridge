import SwiftUI

enum ArtFaceStyle {
    case tile
    case panel
    case thumb

    var padding: CGFloat {
        switch self {
        case .tile: Space.n3
        case .panel: Space.n6
        case .thumb: Space.n1
        }
    }

    var titleStyle: TypeStyle {
        switch self {
        case .tile: .tile
        case .panel: .titleL
        case .thumb: .tileSystem
        }
    }

    var titleLines: Int {
        switch self {
        case .tile: Clamp.tileTitle
        case .panel: Clamp.bigTileTitle
        case .thumb: Clamp.tileTitle
        }
    }

    var systemStyle: TypeStyle? {
        switch self {
        case .tile: .tileSystem
        case .panel: .meta
        case .thumb: nil
        }
    }
}

struct ArtFace: View {
    let title: String
    let system: GameSystem
    let art: TileArt
    let style: ArtFaceStyle

    var body: some View {
        switch art {
        case .loading:
            LoadingFace {
                ArtLabels(title: title, system: system, style: style, onArt: false)
            }
        case .placeholder:
            PlaceholderFace(title: title, system: system, style: style)
        case .image(let loaded):
            ZStack {
                Image(decorative: loaded.image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: Layout.artFillBlur)
                    .opacity(0.55)
                Image(decorative: loaded.image, scale: 1)
                    .resizable()
                    .scaledToFit()
            }
            .clipped()
        }
    }
}

private struct ArtLabels: View {
    let title: String
    let system: GameSystem
    let style: ArtFaceStyle
    let onArt: Bool

    var body: some View {
        VStack(alignment: .leading) {
            Text(displayTitle)
                .typeStyle(style.titleStyle)
                .foregroundStyle(onArt ? Palette.textOnArt : Palette.textSecondary)
                .shadow(color: onArt ? Palette.placeholderTextShadow : .clear, radius: 1, x: 0, y: 1)
                .lineLimit(style.titleLines)
                .multilineTextAlignment(.leading)
                .padding(.trailing, onArt && style == .tile ? Layout.markWidth : 0)
            Spacer(minLength: 0)
            if let systemStyle = style.systemStyle {
                Text(system.displayName)
                    .typeStyle(systemStyle)
                    .fontWeight(.bold)
                    .foregroundStyle(onArt ? Palette.textOnArt : Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayTitle: String {
        guard style == .tile else { return title }
        let width = Layout.tileWidth(for: system.tileAspect) - 2 * style.padding - Layout.markWidth
        return TitleFitter.fit(title, width: width, style: style.titleStyle)
    }
}

private struct PlaceholderFace: View {
    let title: String
    let system: GameSystem
    let style: ArtFaceStyle

    var body: some View {
        let stops = Palette.placeholder(PlaceholderPalette.index(for: title))
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: stops.top, location: 0),
                    .init(color: stops.middle, location: 0.55),
                    .init(color: stops.bottom, location: 1),
                ],
                startPoint: UnitPoint(x: 0.41, y: 0.01),
                endPoint: UnitPoint(x: 0.59, y: 0.99)
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.46),
                    .init(color: Palette.placeholderSheen, location: 0.46),
                    .init(color: Palette.placeholderSheen, location: 0.52),
                    .init(color: .clear, location: 0.52),
                ],
                startPoint: UnitPoint(x: 0.67, y: 0.03),
                endPoint: UnitPoint(x: 0.33, y: 0.97)
            )
            ArtLabels(title: title, system: system, style: style, onArt: true)
                .padding(style.padding)
        }
    }
}

struct LoadingFace<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    var body: some View {
        ZStack {
            Palette.tileLoading
            if !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Palette.tileLoadingSheen, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 1.2)
                    .offset(x: isSweeping ? proxy.size.width : -proxy.size.width * 1.2)
                }
                .onAppear {
                    withAnimation(.linear(duration: Motion.shimmer.seconds).repeatForever(autoreverses: false)) {
                        isSweeping = true
                    }
                }
            }
            content
                .padding(Space.n3)
        }
    }
}
