import SwiftUI

struct EmptyLibraryScreen: View {
    let model: AppModel
    let folder: FolderSummary

    var body: some View {
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: [
                Hint(kind: .move, label: "Move"),
                Hint(kind: .confirm, label: "Select"),
                Hint(kind: .options, label: "Settings"),
            ],
            backdrop: { EmptyView() },
            content: {
                HStack(alignment: .center, spacing: Space.n7) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("No games in \(folder.name)")
                            .typeStyle(.titleL)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(Clamp.messageTitle)
                            .padding(.bottom, Space.n4)
                        MessageParagraph(text: bodyText, isFullPage: true)
                            .padding(.bottom, Space.n5)
                        SystemChipRow()
                            .padding(.bottom, Space.n5)
                        ActionButton(
                            glyph: "folder",
                            label: "Choose Another Folder…",
                            note: "Opens a Finder window. Zip files holding one game work too.",
                            isHighlighted: true
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RowRail(
                        entries: LibraryRows.railEntries(rows: [], scan: nil, isEmpty: true),
                        currentIndex: nil
                    )
                }
                .padding(.horizontal, Layout.marginX)
                .frame(maxHeight: .infinity)
            }
        )
    }

    private var bodyText: String {
        let lead = "Cartridge plays NES, SNES, Genesis, N64 and PS1 games."
        switch folder.fileCount {
        case 0: return "\(lead) This folder is empty."
        case 1: return "\(lead) The one file in this folder is not one of them."
        default: return "\(lead) None of the \(folder.fileCount.formatted()) files in this folder is one of them."
        }
    }
}
