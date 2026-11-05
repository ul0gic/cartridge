import SwiftUI

struct PlayChipsView: View {
    let model: PlayChipsModel
    let safeTop: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.n2) {
            ForEach(model.chips) { chip in
                if chip.kind == .failure {
                    HubMessageView(message: .danger(chip.head, chip.detail))
                } else {
                    ChipView(chip: chip, elapsed: chip.kind == .recording ? model.elapsedText : nil)
                }
            }
        }
        .padding(.trailing, Layout.marginX)
        .padding(.top, safeTop + Space.n2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }
}

private struct ChipView: View {
    let chip: PlayChip
    let elapsed: String?

    var body: some View {
        HStack(spacing: Space.n2) {
            if chip.isBusy {
                Spinner()
            } else if let glyph = chip.glyph {
                GlyphLabel(
                    symbol: glyph,
                    size: Layout.glyphStatus,
                    color: chip.kind == .recording ? Palette.danger : Palette.textPrimary
                )
            }
            Text(chip.head)
                .typeStyle(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
            if let detail = chip.detail {
                Text("· \(detail)")
                    .typeStyle(.meta)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let elapsed {
                Text(elapsed)
                    .typeStyle(TypeStyle.meta.digits)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.n4)
        .frame(height: Layout.chipHeight)
        .hubPlate(radius: Radius.pill)
        .accessibilityElement(children: .combine)
        .onAppear {
            AccessibilityNotification
                .Announcement([chip.head, chip.detail].compactMap(\.self).joined(separator: ". ")).post()
        }
    }
}
