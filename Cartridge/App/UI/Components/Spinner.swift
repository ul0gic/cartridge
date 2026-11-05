import SwiftUI

struct Spinner: View {
    var onAction = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpinning = false

    var body: some View {
        if reduceMotion {
            Image(systemName: "ellipsis")
                .font(.system(size: Layout.spinner, weight: .bold))
                .foregroundStyle(onAction ? Palette.actionText : Palette.textPrimary)
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle()
                    .stroke(
                        onAction ? Palette.actionText.opacity(0.35) : Palette.textTertiary,
                        lineWidth: Layout.spinnerStroke
                    )
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(onAction ? Palette.actionText : Palette.textPrimary, lineWidth: Layout.spinnerStroke)
                    .rotationEffect(.degrees(-135))
            }
            .frame(width: Layout.spinner, height: Layout.spinner)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: Motion.spin.seconds).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
            .accessibilityHidden(true)
        }
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Palette.controlFill)
            .frame(width: Layout.progressWidth, height: Layout.progressHeight)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Palette.focusRing)
                    .frame(width: Layout.progressWidth * min(max(fraction, 0), 1))
            }
            .accessibilityElement()
            .accessibilityLabel("Scan progress")
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
