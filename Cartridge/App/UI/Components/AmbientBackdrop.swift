import SwiftUI

struct AmbientColors: Equatable {
    let id: String
    let top: Color
    let middle: Color
    let bottom: Color

    static let brand = AmbientColors(id: "brand", top: Palette.brand3, middle: Palette.brand2, bottom: Palette.brand1)

    static func placeholder(title: String) -> AmbientColors {
        let index = PlaceholderPalette.index(for: title)
        let stops = Palette.placeholder(index)
        return AmbientColors(id: "ph-\(index)", top: stops.top, middle: stops.middle, bottom: stops.bottom)
    }

    static func art(_ art: ArtColors, id: String) -> AmbientColors {
        AmbientColors(id: id, top: art.top, middle: art.middle, bottom: art.bottom)
    }
}

enum BackdropLayout {
    case library
    case cinematic
    case panel
    case open
}

struct AmbientBackdrop: View {
    let colors: AmbientColors
    let layout: BackdropLayout
    var drawsBase = true
    var intensity = 1.0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if drawsBase {
                Palette.background
            }
            AmbientWash(colors: colors, strength: strength)
                .id(colors.id)
                .transition(.opacity)
            scrim
        }
        .animation(Motion.easeInOut(Motion.ambient).delay(Motion.ambientDelay.seconds), value: colors.id)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var strength: Double {
        (colorScheme == .dark ? Ambient.strengthDark : Ambient.strengthLight) * intensity
    }

    private var showsBleed: Bool {
        !reduceTransparency && contrast != .increased
    }

    private var heroOpacity: Double {
        showsBleed ? 1 - Ambient.heroBleed : 1
    }

    private var rowsOpacity: Double {
        showsBleed ? 1 - Ambient.rowsBleed : 1
    }

    private var rowsScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.background.opacity(0), location: 0),
                .init(color: Palette.background.opacity(0), location: 0.26),
                .init(color: Palette.background.opacity(rowsOpacity), location: 0.4),
                .init(color: Palette.background.opacity(rowsOpacity), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder private var scrim: some View {
        switch layout {
        case .cinematic:
            rowsScrim
        case .library:
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Palette.background.opacity(heroOpacity), location: 0),
                        .init(color: Palette.background.opacity(heroOpacity), location: 0.52),
                        .init(color: Palette.background.opacity(0), location: 0.74),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                rowsScrim
            }
        case .open:
            EmptyView()
        case .panel:
            LinearGradient(
                stops: [
                    .init(color: Palette.background.opacity(0), location: 0),
                    .init(color: Palette.background.opacity(0), location: 0.4),
                    .init(color: Palette.background.opacity(heroOpacity), location: 0.58),
                    .init(color: Palette.background.opacity(heroOpacity), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private struct WashLayer {
    let color: Color
    let center: CGPoint
    let radii: CGSize
    let fade: CGFloat
}

private struct AmbientWash: View {
    let colors: AmbientColors
    let strength: Double

    private static let overscan: CGFloat = 0.1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let layers = [
                WashLayer(
                    color: colors.bottom,
                    center: CGPoint(x: 0.8, y: 0.24),
                    radii: CGSize(width: 0.48, height: 0.62),
                    fade: 0.7
                ),
                WashLayer(
                    color: colors.middle,
                    center: CGPoint(x: 1.0, y: 0.7),
                    radii: CGSize(width: 0.4, height: 0.5),
                    fade: 0.72
                ),
                WashLayer(
                    color: colors.top,
                    center: CGPoint(x: 0.52, y: 0),
                    radii: CGSize(width: 0.42, height: 0.46),
                    fade: 0.7
                ),
            ]
            ZStack {
                ForEach(0..<layers.count, id: \.self) { index in
                    let wash = layers[index]
                    let tint = wash.color.mix(with: Palette.background, by: 1 - strength)
                    EllipticalGradient(
                        stops: [.init(color: tint, location: 0), .init(color: tint.opacity(0), location: wash.fade)],
                        center: .center,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.5
                    )
                    .frame(width: width * wash.radii.width * 2, height: height * wash.radii.height * 2)
                    .position(
                        x: width * (Self.overscan + wash.center.x),
                        y: height * (Self.overscan + wash.center.y)
                    )
                }
            }
            .frame(
                width: width * (1 + 2 * Self.overscan),
                height: height * (1 + 2 * Self.overscan),
                alignment: .topLeading
            )
            .blur(radius: Layout.blurAmbient)
            .saturation(Layout.saturateAmbient)
            .position(x: width / 2, y: height / 2)
        }
    }
}
