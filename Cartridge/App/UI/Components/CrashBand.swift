import SwiftUI

struct CrashBand: View {
    let gameTitle: String
    let glyphs: HintGlyphs?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.n4) {
            GlyphLabel(symbol: "xmark.octagon.fill", size: Layout.glyphMessage, color: Palette.danger)
            Text(
                "\(Text("\(gameTitle) stopped unexpectedly.").fontWeight(.semibold).foregroundStyle(Palette.textPrimary)) \(Self.detail)"
            )
            .typeStyle(.body)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.n2) {
                if let glyphs {
                    GlyphLabel(symbol: glyphs.confirm, size: Layout.glyphHint)
                } else {
                    Keycap(label: "Return")
                }
                Text("OK")
                    .typeStyle(.hint)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .padding(.horizontal, Layout.marginX)
        .frame(height: Layout.bandHeight)
        .background(Palette.bandDangerFill)
        .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gameTitle) stopped unexpectedly. \(Self.detail)")
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            AccessibilityNotification.Announcement("\(gameTitle) stopped unexpectedly. \(Self.detail)").post()
        }
    }

    private static let detail = [
        "Play since your last save state is lost.",
        "Your battery save from before this session is kept.",
    ].joined(separator: " ")
}
