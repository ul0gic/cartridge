import SwiftUI

struct GlassChip: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Space.n2) {
            if let symbol {
                GlyphLabel(symbol: symbol, size: Layout.glyphInline, color: Palette.textPrimary)
            }
            Text(text)
                .typeStyle(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Space.n4)
        .padding(.vertical, Space.n2)
        .glassSurface(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct MetadataChips: View {
    let metadata: GameMetadata?

    var body: some View {
        let chips = Self.chips(for: metadata)
        if !chips.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.n3) { chipViews(chips) }
                VStack(alignment: .leading, spacing: Space.n2) { chipViews(chips) }
            }
        }
    }

    private func chipViews(_ chips: [(String, String)]) -> some View {
        ForEach(chips, id: \.1) { chip in
            GlassChip(text: chip.1, symbol: chip.0)
        }
    }

    private static func chips(for metadata: GameMetadata?) -> [(String, String)] {
        guard let metadata else { return [] }
        return [
            metadata.genre.map { ("tag", $0) },
            metadata.year.map { ("calendar", String($0)) },
            metadata.players.map { ("gamecontroller", MetadataText.players($0)) },
        ].compactMap(\.self)
    }
}

struct SystemBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .typeStyle(.meta)
            .fontWeight(.bold)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.n3)
            .padding(.vertical, Space.n1)
            .glassSurface(in: Capsule())
    }
}
