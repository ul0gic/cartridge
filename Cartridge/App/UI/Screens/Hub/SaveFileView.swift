import SwiftUI

struct SaveFileView: View {
    let page: SaveFilePage
    let isRestarting: Bool
    let confirmGlyph: String?

    var body: some View {
        ColumnScroll(scrollTarget: page.target) {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: Space.n2) {
            if isRestarting {
                InfoRow(message: Self.restarting(unit: page.unit))
            } else if !page.hasSave {
                InfoRow(message: .info(
                    "This game keeps no save file",
                    "It doesn’t save on its own. Use Save States to keep your place."
                ))
            } else if page.isListing {
                ForEach(page.backups) { backup in
                    BackupRow(page: page, backup: backup, confirmGlyph: confirmGlyph)
                }
            } else {
                ActionRows(page: page, confirmGlyph: confirmGlyph)
            }
        }
    }

    private static func restarting(unit: String) -> HubMessage {
        var message = HubMessage.info(
            "Restarting from power-on…",
            "The game reads the restored \(unit) as it starts."
        )
        message.showsSpinner = true
        return message
    }
}

struct InfoRow: View {
    let message: HubMessage

    var body: some View {
        HStack(alignment: .top, spacing: Space.n3) {
            if message.showsSpinner {
                Spinner()
                    .frame(width: Layout.glyphStatus, height: Layout.glyphStatus)
            } else {
                GlyphLabel(symbol: message.glyph ?? "info.circle", size: Layout.glyphStatus)
            }
            VStack(alignment: .leading, spacing: Space.n1) {
                Text(message.head)
                    .typeStyle(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                if let detail = message.detail {
                    Text(detail)
                        .typeStyle(.meta)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityElement(children: .combine)
    }
}

private struct ActionRows: View {
    let page: SaveFilePage
    let confirmGlyph: String?

    var body: some View {
        VStack(spacing: Space.n2) {
            row(.backUp, glyph: "doc.on.doc", label: "Back Up", detail: backUpDetail)
            if !page.backups.isEmpty {
                row(.restore, glyph: "clock.arrow.circlepath", label: "Restore", detail: restoreDetail, chevron: true)
            } else {
                disabledRestore
            }
            row(.importSave, glyph: "tray.and.arrow.down", label: "Import…", detail: importDetail)
        }
    }

    private var backUpDetail: HubDetail {
        page.isJustBackedUp ? .success("Backed up just now") : .text("Keep a copy of the \(page.unit) as it is now")
    }

    private var restoreDetail: HubDetail {
        guard let newest = page.backups.first else { return .text("No backups yet") }
        let count = page.backups.count
        return .text("\(count) \(count == 1 ? "backup" : "backups"), newest \(HubFormat.date(newest.createdAt))")
    }

    private var importDetail: HubDetail {
        page.arming.isArmed(.importSave)
            ? .armed(verb: "import")
            : .text("Bring in a \(page.unit) file from your Mac")
    }

    private var disabledRestore: some View {
        HubRowFrame(state: .disabled) {
            HStack(spacing: Space.n4) {
                GlyphLabel(symbol: "clock.arrow.circlepath", size: Layout.glyphStatus, color: Palette.textSecondary)
                HubRowText(label: "Restore", detail: .text("No backups yet"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Restore, no backups yet")
    }

    private func row(
        _ target: SaveFileTarget,
        glyph: String,
        label: String,
        detail: HubDetail,
        chevron: Bool = false
    ) -> some View {
        HubRowFrame(state: page.target == target ? .highlighted : .resting) {
            HStack(spacing: Space.n4) {
                if page.busy == target {
                    Spinner(onAction: page.target == target)
                        .frame(width: Layout.glyphStatus, height: Layout.glyphStatus)
                } else {
                    RowGlyph(symbol: glyph)
                }
                HubRowText(label: label, detail: detail, confirmGlyph: confirmGlyph)
                Spacer(minLength: Space.n3)
                if chevron {
                    RowGlyph(symbol: "chevron.right", size: Layout.glyphInline)
                }
            }
        }
        .id(target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

private struct BackupRow: View {
    let page: SaveFilePage
    let backup: SaveBackup
    let confirmGlyph: String?

    var body: some View {
        let target = SaveFileTarget.backup(backup.url)
        HubRowFrame(state: page.target == target ? .highlighted : .resting) {
            HStack(spacing: Space.n4) {
                if page.busy == target {
                    Spinner(onAction: page.target == target)
                        .frame(width: Layout.glyphStatus, height: Layout.glyphStatus)
                } else {
                    RowGlyph(symbol: "memorychip")
                }
                HubRowText(
                    label: HubFormat.sentenceDate(backup.createdAt),
                    detail: detail(target),
                    confirmGlyph: confirmGlyph
                )
                Spacer(minLength: Space.n3)
            }
        }
        .id(target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(HubFormat.date(backup.createdAt)), \(HubFormat.fileSize(backup.bytes))")
        .accessibilityAddTraits(.isButton)
    }

    private func detail(_ target: SaveFileTarget) -> HubDetail {
        page.arming.isArmed(target) ? .armed(verb: "restore") : .text(HubFormat.fileSize(backup.bytes))
    }
}

struct RowGlyph: View {
    let symbol: String
    var size = Layout.glyphStatus

    @Environment(\.isHubRowInverted) private var isInverted
    @Environment(\.isHubRowDisabled) private var isDisabled

    var body: some View {
        GlyphLabel(
            symbol: symbol,
            size: size,
            color: isInverted ? Palette.actionText : (isDisabled ? Palette.textSecondary : Palette.textPrimary)
        )
    }
}
