import SwiftUI

private struct FocusLift: ViewModifier {
    let isHighlighted: Bool
    let radius: CGFloat
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .focusRing(isHighlighted, radius: radius)
            .shadow(
                color: isHighlighted ? Palette.shadowLift : .clear,
                radius: Layout.shadowLiftBlur / 2,
                x: 0,
                y: Layout.shadowLiftOffset
            )
            .scaleEffect(isHighlighted && !reduceMotion ? scale : 1)
            .animation(Motion.easeOut(Motion.focus), value: isHighlighted)
            .zIndex(isHighlighted ? 1 : 0)
    }
}

extension View {
    func focusLift(
        _ isHighlighted: Bool,
        radius: CGFloat = Radius.tile,
        scale: CGFloat = Layout.focusScale
    ) -> some View {
        modifier(FocusLift(isHighlighted: isHighlighted, radius: radius, scale: scale))
    }
}

struct SceneArt: View {
    let source: BackdropSource?

    var body: some View {
        switch source {
        case .screenshot(let art):
            Image(decorative: art.image, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
        case .boxArt(let art):
            Image(decorative: art.image, scale: 1)
                .resizable()
                .scaledToFill()
                .blur(radius: Layout.backdropBlurHeavy / 2)
                .scaleEffect(1.2)
        case .collage:
            Image("WelcomeCollage")
                .resizable()
                .scaledToFill()
        case .console(let system):
            Image(system.backdropImage)
                .resizable()
                .scaledToFill()
        case nil:
            Palette.surface
        }
    }
}

struct MomentCard: View {
    let model: AppModel
    let game: GameRecord
    let isHighlighted: Bool

    @State private var scene: BackdropSource?
    @State private var art = TileArt.loading

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SceneArt(source: scene)
                .frame(width: Layout.momentWidth, height: Layout.tileHeight)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            HStack(alignment: .bottom, spacing: Space.n3) {
                ArtFace(title: game.title, system: game.system, art: art, style: .tile)
                    .frame(width: Layout.momentCoverHeight * game.system.tileAspect, height: Layout.momentCoverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.keycap))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.title)
                        .typeStyle(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if let date = model.resumeDate(for: game) {
                        Text("Resume · \(DisplayDate.text(date))")
                            .typeStyle(.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(Space.n3)
        }
        .frame(width: Layout.momentWidth, height: Layout.tileHeight)
        .focusLift(isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.title), \(game.system.displayName), resume")
        .accessibilityAddTraits(.isButton)
        .task(id: game.id) {
            scene = await model.moment(for: game)
            art = await model.tileArt(for: game)
        }
    }
}

struct ConsoleCard: View {
    let model: AppModel
    let summary: ConsoleSummary
    let isHighlighted: Bool
    var width = Layout.momentWidth
    var height = Layout.tileHeight
    var focusScale = Layout.focusScale

    var body: some View {
        let palette = ConsolePalette.of(summary.system)
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [palette.card, palette.card.mix(with: .black, by: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(Layout.consoleCardSheen), location: 0),
                    .init(color: .white.opacity(0.02), location: 0.46),
                    .init(color: .clear, location: 0.47),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            CoverFan(model: model, covers: summary.covers, height: fanHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, Space.n3)
                .offset(y: height * 0.12)
            VStack(alignment: .leading, spacing: Space.n1) {
                Text(summary.system.displayName)
                    .typeStyle(height > Layout.tileHeight ? .titleM : .headline)
                Text(LibraryRows.gameCount(summary.gameCount))
                    .typeStyle(.caption)
                if summary.inProgress > 0 {
                    Text("\(summary.inProgress) in progress")
                        .typeStyle(.caption)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(palette.cardText)
            .padding(Space.n4)
            HStack(spacing: 0) {
                ForEach(palette.stripe.indices, id: \.self) { index in
                    palette.stripe[index]
                }
            }
            .frame(height: Layout.consoleStripeHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.art)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.04), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: Layout.strokeHair
                )
        }
        .shadow(color: isHighlighted ? palette.lead.opacity(0.5) : .clear, radius: Layout.consoleCardGlow)
        .focusLift(isHighlighted, radius: Radius.art, scale: focusScale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.system.displayName), \(LibraryRows.gameCount(summary.gameCount))")
        .accessibilityAddTraits(.isButton)
    }
}

extension ConsoleCard {
    private var fanHeight: CGFloat {
        min(height * 0.62, width * 0.36 / summary.system.tileAspect)
    }
}

private struct CoverFan: View {
    let model: AppModel
    let covers: [GameRecord]
    let height: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(covers.enumerated().reversed()), id: \.element.id) { index, game in
                FanCover(model: model, game: game, height: height)
                    .rotationEffect(.degrees(Double(index - 1) * 9), anchor: .bottom)
                    .offset(x: CGFloat(index - 1) * height * 0.32)
            }
        }
    }
}

private struct FanCover: View {
    let model: AppModel
    let game: GameRecord
    let height: CGFloat

    @State private var art = TileArt.loading

    var body: some View {
        ArtFace(title: game.title, system: game.system, art: art, style: .tile)
            .frame(width: height * game.system.tileAspect, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.keycap))
            .shadow(color: .black.opacity(0.55), radius: 10, y: 6)
            .task(id: game.artStatus) { art = await model.tileArt(for: game) }
    }
}
