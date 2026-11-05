import SwiftUI

struct DeniedScreen: View {
    let model: AppModel

    var body: some View {
        let folder = model.deniedFolder
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: false,
            hints: [Hint(kind: .move, label: "Move"), Hint(kind: .confirm, label: "Select")],
            backdrop: { WallBackdrop() },
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    GlyphLabel(symbol: "lock", size: Layout.glyphMessage, color: Palette.danger)
                        .padding(.bottom, Space.n4)
                    Text("Cartridge can’t open \(folder.name)")
                        .typeStyle(.titleL)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(Clamp.messageTitle)
                        .padding(.bottom, Space.n4)
                    MessageParagraph(
                        text: "macOS is blocking access to your ROM folder. Open System Settings › Privacy & "
                            + "Security › Files & Folders, turn on \(folder.name) for Cartridge, then come back.",
                        isFullPage: true
                    )
                    .padding(.bottom, Space.n6)
                    ButtonGroup {
                        ActionButton(glyph: nil, label: "Open System Settings", isHighlighted: model.focusedButton == 0)
                        ActionButton(
                            glyph: "folder",
                            label: "Choose Another Folder…",
                            note: "Opens a Finder window.",
                            isHighlighted: model.focusedButton == 1
                        )
                        ActionButton(
                            glyph: "arrow.clockwise",
                            label: "Try Again",
                            isHighlighted: model.focusedButton == 2
                        )
                    }
                }
                .pageColumn(width: Layout.welcomeWidth)
            }
        )
    }
}
