import SwiftUI

struct CollageBackdrop: View {
    var dimming = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isZoomed = false

    var body: some View {
        Color.clear.overlay { layers }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var layers: some View {
        ZStack {
            Image("WelcomeCollage")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .blur(radius: Layout.collageBlur)
                .scaleEffect(isZoomed && !reduceMotion ? Layout.collageZoom : 1)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: Layout.collageZoomSeconds).repeatForever(autoreverses: true),
                    value: isZoomed
                )
                .onAppear { isZoomed = true }
            Palette.background.opacity(reduceTransparency ? 0.96 : dimming)
            LinearGradient(
                stops: [
                    .init(color: Palette.background.opacity(0.96), location: 0),
                    .init(color: Palette.background.opacity(0.72), location: 0.45),
                    .init(color: Palette.background.opacity(0.1), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
