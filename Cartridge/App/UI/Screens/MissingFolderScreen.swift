import SwiftUI

struct MissingFolderScreen: View {
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
                VStack(alignment: .leading, spacing: 0) {
                    Text("Can’t find \(folder.name)")
                        .typeStyle(.titleL)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(Clamp.messageTitle)
                        .padding(.bottom, Space.n4)
                    MessageParagraph(
                        text: "The folder at \(folder.path) isn’t there. If it’s on an external drive, connect the drive "
                            + "and choose Try Again.",
                        isFullPage: true
                    )
                    .padding(.bottom, Space.n5)
                    FolderChip(glyph: "folder.badge.questionmark", name: folder.name, path: folder.path)
                        .padding(.bottom, Space.n6)
                    ButtonGroup {
                        ActionButton(
                            glyph: "arrow.clockwise",
                            label: "Try Again",
                            isHighlighted: model.focusedButton == 0
                        )
                        ActionButton(
                            glyph: "folder",
                            label: "Choose Folder…",
                            note: "Opens a Finder window.",
                            isHighlighted: model.focusedButton == 1
                        )
                    }
                }
                .pageColumn()
            }
        )
    }
}
