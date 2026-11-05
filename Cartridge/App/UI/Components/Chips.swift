import SwiftUI

struct SystemChip: View {
    let system: GameSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(system.displayName)
                .typeStyle(.body)
                .fontWeight(.bold)
                .foregroundStyle(Palette.textPrimary)
            Text(system.fileExtensions.map { ".\($0)" }.joined(separator: " "))
                .typeStyle(.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlPlate()
        .accessibilityElement(children: .combine)
    }
}

struct SystemChipRow: View {
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Space.n4),
        count: Layout.systemChipColumns
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.n4) {
            ForEach(GameSystem.allCases, id: \.self) { system in
                SystemChip(system: system)
            }
        }
        .frame(maxWidth: Layout.systemChipGridWidth)
    }
}

struct FolderChip: View {
    let glyph: String
    let name: String
    let path: String

    var body: some View {
        HStack(spacing: Space.n3) {
            GlyphLabel(symbol: glyph, size: Layout.glyphStatus, color: Palette.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .typeStyle(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                Text(path)
                    .typeStyle(.meta)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n4)
        .controlPlate()
        .accessibilityElement(children: .combine)
    }
}

struct ScanFolderLine: View {
    let name: String
    let path: String

    var body: some View {
        HStack(spacing: Space.n2) {
            GlyphLabel(symbol: "folder", color: Palette.textSecondary)
            Text(name)
                .typeStyle(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
            Text(path)
                .typeStyle(.meta)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
