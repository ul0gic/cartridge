import SwiftUI

struct DiscView: View {
    let page: DiscPage

    var body: some View {
        VStack(spacing: Space.n2) {
            ForEach(0..<page.discCount, id: \.self) { index in
                let isInDrive = index == page.discInDrive
                HubRowFrame(state: isInDrive ? .disabled : (page.highlighted == index ? .highlighted : .resting)) {
                    HStack(spacing: Space.n4) {
                        if page.busy == index {
                            Spinner(onAction: page.highlighted == index)
                                .frame(width: Layout.glyphStatus, height: Layout.glyphStatus)
                        } else {
                            GlyphLabel(symbol: "opticaldisc", size: Layout.glyphStatus, color: glyphColor(index))
                        }
                        HubRowText(
                            label: "Disc \(index + 1)",
                            detail: .text(isInDrive
                                ? "In the drive"
                                : "Take out disc \(page.discInDrive + 1), put in disc \(index + 1)")
                        )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Disc \(index + 1), \(isInDrive ? "in the drive" : "put in")")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func glyphColor(_ index: Int) -> Color {
        if index == page.discInDrive {
            return Palette.textSecondary
        }
        return page.highlighted == index ? Palette.actionText : Palette.textPrimary
    }
}
