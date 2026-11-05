import SwiftUI

private struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let isInteractive: Bool
    let opaqueFill: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.consoleSystem) private var consoleSystem

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(opaqueFill, in: shape)
                .overlay { shape.strokeBorder(Palette.keycapStroke, lineWidth: Layout.strokeHair) }
        } else {
            content
                .glassEffect(Glass.regular.tint(glassTint).interactive(isInteractive), in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.34), .white.opacity(0.03), edgeLight.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: Layout.strokeHair
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    private var edgeLight: Color {
        consoleSystem.map { ConsolePalette.of($0).light } ?? .white
    }

    private var glassTint: Color {
        if let tint {
            return tint
        }
        guard let consoleSystem else { return Palette.glassTint }
        return ConsolePalette.of(consoleSystem).shadow.opacity(0.3)
    }
}

private struct ControlPlateModifier: ViewModifier {
    let radius: CGFloat
    let isActive: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background(isActive ? Palette.controlFill : .clear, in: shape)
            .overlay {
                shape.strokeBorder(isActive ? stroke : .clear, lineWidth: Layout.strokeHair)
            }
    }

    private var stroke: Color {
        contrast == .increased ? Palette.keycapStroke : Palette.controlStroke
    }
}

struct FocusRing: View {
    let radius: CGFloat

    var body: some View {
        let gap = Layout.focusGapWidth
        let ring = Layout.focusRingWidth
        ZStack {
            RoundedRectangle(cornerRadius: radius + gap)
                .strokeBorder(Palette.focusGap, lineWidth: gap)
                .padding(-gap)
            RoundedRectangle(cornerRadius: radius + gap + ring)
                .strokeBorder(Palette.focusRing, lineWidth: ring)
                .padding(-(gap + ring))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func plate(radius: CGFloat = Radius.control) -> some View {
        glassSurface(in: RoundedRectangle(cornerRadius: radius))
    }

    func glassSurface(
        in shape: some InsettableShape,
        tint: Color? = nil,
        isInteractive: Bool = false,
        opaqueFill: Color = Palette.surface
    ) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, tint: tint, isInteractive: isInteractive, opaqueFill: opaqueFill))
    }

    func controlPlate(radius: CGFloat = Radius.control, isActive: Bool = true) -> some View {
        modifier(ControlPlateModifier(radius: radius, isActive: isActive))
    }

    func focusRing(_ isActive: Bool, radius: CGFloat) -> some View {
        overlay {
            FocusRing(radius: radius)
                .opacity(isActive ? 1 : 0)
                .transaction(value: isActive) { $0.animation = nil }
        }
    }
}
