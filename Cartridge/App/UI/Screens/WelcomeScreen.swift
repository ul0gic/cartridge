import SwiftUI

struct WelcomeScreen: View {
    let model: AppModel

    var body: some View {
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: false,
            hints: [Hint(kind: .confirm, label: "Choose ROM Folder")],
            backdrop: { WallBackdrop() },
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    AppIconImage(size: Layout.welcomeIcon)
                        .padding(.bottom, Space.n5)
                    Text("Cartridge")
                        .typeStyle(.display)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.bottom, Space.n5)
                    MessageParagraph(
                        text: "Choose the folder that holds your games. Cartridge finds them, fetches box art "
                            + "and builds your library. It never changes your files.",
                        isFullPage: true
                    )
                    .padding(.bottom, Space.n6)
                    ActionButton(
                        glyph: "folder",
                        label: "Choose ROM Folder…",
                        note: "Opens a Finder window. This is the only step that needs the trackpad or keyboard.",
                        isHighlighted: true
                    )
                    .padding(.bottom, Space.n6)
                    SystemChipRow()
                    Text("Zip files holding one game work too.")
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, Space.n3)
                }
                .pageColumn(width: Layout.welcomeWidth)
            }
        )
    }
}
