import SwiftUI

struct ConsoleFrame: View {
    let system: GameSystem
    var artTop: CGFloat = 0
    var artHeight: CGFloat = 0
    var showsArtwork = true
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            ConsoleFrameLayer(
                system: system,
                artTop: artTop,
                artHeight: artHeight,
                showsArtwork: showsArtwork,
                isSimplified: reduceTransparency || contrast == .increased
            )
            .id(system)
            .transition(.opacity)
        }
        .opacity(intensity)
        .animation(reduceMotion ? nil : Motion.easeInOut(Motion.ambient), value: system)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ConsoleFrameLayer: View {
    let system: GameSystem
    let artTop: CGFloat
    let artHeight: CGFloat
    let showsArtwork: Bool
    let isSimplified: Bool

    private var palette: ConsolePalette {
        .of(system)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if showsArtwork {
                    Palette.background
                }
                shellColor
                    .mask { Image("ConsoleFrameMask").resizable() }
                if !isSimplified {
                    illumination(size: proxy.size)
                    if showsArtwork {
                        artwork(size: proxy.size)
                    }
                }
                edgeLight
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var shellColor: some View {
        LinearGradient(
            stops: [
                .init(color: palette.lead, location: 0),
                .init(color: palette.lead.mix(with: .black, by: 0.22), location: 0.25),
                .init(color: palette.shadow, location: 0.62),
                .init(color: palette.lead, location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(isSimplified ? 0.75 : 0.36), location: 0.18),
                    .init(color: .black.opacity(0.1), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func illumination(size: CGSize) -> some View {
        ZStack {
            RadialGradient(
                colors: [palette.light.opacity(0.32), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: size.width * 0.48
            )
            RadialGradient(
                colors: [palette.lead.opacity(0.48), .clear],
                center: .init(x: 0.08, y: 1),
                startRadius: 0,
                endRadius: size.width * 0.55
            )
            LinearGradient(
                colors: [palette.light.opacity(0.13), .clear, .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .mask { Image("ConsoleFrameMask").resizable() }
    }

    private func artwork(size: CGSize) -> some View {
        let width = size.width * Layout.consoleFrameArtShare
        let height = artHeight + Layout.consoleFrameArtExtension
        return Image(system.backdropImage)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .mask { artworkMask }
            .offset(x: size.width - width, y: artTop - Layout.consoleFrameArtLift)
    }

    private var artworkMask: some View {
        AngledBlock()
            .fill(.black)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.32),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.72),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    private var edgeLight: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [palette.light.opacity(0.7), palette.lead.opacity(0.1), palette.light.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: Layout.consoleFrameEdge)
            LinearGradient(
                colors: [palette.light.opacity(0.85), palette.lead.opacity(0.6), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: Layout.consoleFrameEdge)
        }
    }
}

private struct AngledBlock: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct ConsoleWell: View {
    let system: GameSystem

    var body: some View {
        let palette = ConsolePalette.of(system)
        let shape = RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
        shape
            .fill(Palette.background.gradient)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [palette.light.opacity(0.48), .white.opacity(0.06), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: Layout.strokeHair
                )
            }
            .shadow(color: .black.opacity(0.3), radius: Space.n5, y: Space.n3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ConsoleWellMask: Shape {
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inset = Layout.consoleFrameInset + Layout.strokeHair
        let panel = CGRect(
            x: rect.minX + inset,
            y: rect.minY + topInset + Layout.strokeHair,
            width: max(0, rect.width - inset * 2),
            height: max(0, rect.height - topInset - bottomInset - Layout.strokeHair * 2)
        )
        return RoundedRectangle(cornerRadius: Radius.sheet - Layout.strokeHair, style: .continuous)
            .path(in: panel)
    }
}
