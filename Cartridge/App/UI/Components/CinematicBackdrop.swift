import SwiftUI

enum BackdropStyle: Equatable {
    case hero
    case detail
    case moment(GameSystem)
}

struct CinematicBackdrop: View {
    let source: BackdropSource
    var style = BackdropStyle.hero
    var heightFraction: CGFloat = Layout.backdropHeightFraction

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                layer(canvas: proxy.size)
                    .id(source.id)
                    .transition(.opacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
            .animation(Motion.easeInOut(Motion.ambient).delay(Motion.ambientDelay.seconds), value: source.id)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layer(canvas: CGSize) -> some View {
        if case .moment(let system) = style, case .screenshot(let frame) = source {
            MomentLayer(frame: frame, system: system, canvas: canvas)
        } else {
            BackdropLayer(source: source, style: style, canvas: canvas, heightFraction: heightFraction)
        }
    }
}

private struct MomentLayer: View {
    let frame: LoadedArt
    let system: GameSystem
    let canvas: CGSize

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .topLeading) {
            picture
            ConsoleFrame(system: system, showsArtwork: false, intensity: Layout.consoleFrameDetailStrength)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(Layout.momentScrimLeft), location: 0),
                    .init(color: .clear, location: Layout.momentScrimLeftEnd),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: Layout.momentScrimBottomStart),
                    .init(color: .black.opacity(Layout.momentScrimBottom), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(colors: [.black.opacity(Layout.momentScrimTop), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Layout.momentScrimTopHeight)
            if reduceTransparency || contrast == .increased {
                Palette.background.opacity(Layout.detailDim)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    private var picture: some View {
        let width = CGFloat(frame.image.width)
        let height = CGFloat(frame.image.height)
        let scale = max(canvas.width / width, canvas.height / height)
        let size = CGSize(width: width * scale, height: height * scale)
        return Image(decorative: frame.image, scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: size.width, height: size.height)
            .offset(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) * Layout.momentFocusY)
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .clipped()
    }
}

private struct BackdropLayer: View {
    let source: BackdropSource
    let style: BackdropStyle
    let canvas: CGSize
    let heightFraction: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var drifting = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            picture
                .frame(width: canvas.width * share, height: canvas.height * heightFraction)
                .clipped()
                .mask { edgeFalloff }
            readabilityScrim
            if style != .hero {
                Palette.background.opacity(Layout.detailDim)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topTrailing)
        .onAppear { drifting = !reduceMotion }
    }

    private var share: CGFloat {
        if case .screenshot = source, style == .hero {
            return Layout.backdropImageShare
        }
        return 1
    }

    @ViewBuilder private var picture: some View {
        switch source {
        case .screenshot(let art):
            Image(decorative: art.image, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .scaleEffect(drifting ? Layout.backdropDriftScale : 1, anchor: .topLeading)
                .animation(drift, value: drifting)
                .overlay { Scanlines() }
        case .boxArt(let art):
            Image(decorative: art.image, scale: 1)
                .resizable()
                .scaledToFill()
                .blur(radius: Layout.backdropBlurHeavy)
                .scaleEffect(1.3)
                .opacity(0.55)
        case .collage:
            Image("WelcomeCollage")
                .resizable()
                .scaledToFill()
                .blur(radius: Layout.backdropBlur)
                .opacity(0.6)
        case .console(let system):
            Image(system.backdropImage)
                .resizable()
                .scaledToFill()
                .scaleEffect(drifting ? Layout.backdropDriftScale : 1, anchor: .trailing)
                .animation(drift, value: drifting)
        }
    }

    private var bottomFadeStart: CGFloat {
        if case .console = source {
            return Layout.consoleBackdropFadeStart
        }
        return 0.45
    }

    private var drift: Animation? {
        drifting ? .easeInOut(duration: Motion.backdropDrift.seconds).repeatForever(autoreverses: true) : nil
    }

    private var edgeFalloff: some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.38)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: bottomFadeStart), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var readabilityScrim: some View {
        let floor = reduceTransparency || contrast == .increased ? 0.35 : 0
        return LinearGradient(
            stops: [
                .init(color: Palette.background.opacity(0.92), location: 0),
                .init(color: Palette.background.opacity(0.55 + floor), location: 0.32),
                .init(color: Palette.background.opacity(0.12 + floor), location: 0.62),
                .init(color: Palette.background.opacity(floor), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: Layout.scanlineThickness)),
                    with: .color(.black.opacity(0.22))
                )
                y += Layout.scanlinePitch
            }
        }
        .allowsHitTesting(false)
    }
}
