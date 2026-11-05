import SwiftUI

struct XboxFirmwareNeededContent: View {
    let model: AppModel

    private static let shownLines = 2

    private var lines: [XboxFirmwareLine] {
        model.xboxFirmwareImport?.lines(installed: model.dependencies.xboxFirmware.installed) ?? []
    }

    private var chips: some View {
        ForEach(XboxFirmwareFile.allCases, id: \.self) { file in
            XboxFirmwareChip(file: file, isReady: model.dependencies.xboxFirmware.installed.contains(file))
        }
    }

    var body: some View {
        MessageHead(kind: .warning, text: "Xbox BIOS needed")
        MessageParagraph(
            text: "Xbox games need two files from an Xbox console: its boot ROM and a BIOS. "
                + "Cartridge checks each file by what is inside it, so the names don’t matter, "
                + "and keeps its own copy on this Mac. It makes the Xbox hard drive itself."
        )
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.n3) { chips }
            VStack(alignment: .leading, spacing: Space.n3) { chips }
        }
        .padding(.top, Space.n4)
        .padding(.bottom, Space.n6)
        results
        ButtonGroup {
            ActionButton(
                glyph: "folder",
                label: "Choose Folder…",
                note: "Opens a Finder window. Pick the folder with the trackpad or keyboard.",
                isHighlighted: model.focusedButton == 0
            )
        }
    }

    @ViewBuilder private var results: some View {
        let lines = lines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Space.n2) {
                ForEach(lines.prefix(Self.shownLines)) { line in
                    InlineResult(kind: line.kind, lead: line.lead, rest: line.rest)
                }
                if lines.count > Self.shownLines {
                    Text(Self.moreNote(lines.count - Self.shownLines))
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: Layout.measure, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, Space.n5)
        }
    }

    private static func moreNote(_ count: Int) -> String {
        let files = count == 1 ? "1 more file" : "\(count.formatted()) more files"
        return "And \(files) Cartridge can’t use. Settings › Xbox BIOS lists every file."
    }
}

struct XboxFirmwareReadyContent: View {
    let model: AppModel

    var body: some View {
        MessageHead(kind: .success, text: "Xbox BIOS ready")
        if let result = model.xboxFirmwareImport {
            MessageParagraph(
                text: "Found \(result.imported.map(\.importedName).sentenceList) in \(result.folderName). "
                    + "Cartridge keeps its own copies, so the original files stay where they are."
            )
            .padding(.bottom, Space.n5)
        }
        ActionButton(glyph: "play.fill", label: "Play", isHighlighted: true)
    }
}

struct XboxFirmwareChip: View {
    let file: XboxFirmwareFile
    let isReady: Bool

    var body: some View {
        HStack(spacing: Space.n3) {
            if isReady {
                GlyphLabel(symbol: "checkmark.circle.fill", size: Layout.glyphStatus, color: Palette.success)
            } else {
                GlyphLabel(symbol: "circle.dashed", size: Layout.glyphStatus, color: Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(file.chipName)
                    .typeStyle(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                Text(isReady ? "Ready" : file.chipDetail)
                    .typeStyle(.meta)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.vertical, Space.n2)
        .padding(.horizontal, Space.n4)
        .controlPlate()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isReady ? "\(file.chipName), ready" : "\(file.chipName), needed, \(file.chipDetail)")
    }
}
