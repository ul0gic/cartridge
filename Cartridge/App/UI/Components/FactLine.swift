import SwiftUI

struct FactLine: View {
    let glyph: String
    var glyphColor = Palette.textPrimary
    let lead: String
    let rest: String

    var body: some View {
        HStack(spacing: Space.n3) {
            GlyphLabel(symbol: glyph, color: glyphColor)
            Text("\(Text(lead).fontWeight(.semibold).foregroundStyle(Palette.textPrimary)) \(rest)")
                .typeStyle(.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
