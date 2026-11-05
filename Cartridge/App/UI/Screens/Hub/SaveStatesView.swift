import SwiftUI

struct SaveStatesView: View {
    let page: SaveStatesPage
    let confirmGlyph: String?

    var body: some View {
        ColumnScroll(scrollTarget: page.highlighted) {
            VStack(spacing: Space.n2) {
                if page.showsOwnSavesNote {
                    HubMessageView(message: .info(
                        "Slots include this game’s own saves",
                        "Loading a slot also returns the game’s own saves to that moment."
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Space.n2)
                }
                ForEach(SlotNumber.all, id: \.self) { slot in
                    SlotRow(page: page, slot: slot, confirmGlyph: confirmGlyph)
                        .id(slot)
                }
            }
        }
    }
}

private struct SlotRow: View {
    let page: SaveStatesPage
    let slot: SlotNumber
    let confirmGlyph: String?

    var body: some View {
        let record = page.slots[slot]
        let isHighlighted = page.highlighted == slot
        let isOpen = page.open == slot
        let state: HubRowState = isOpen ? .open : (isHighlighted ? .highlighted : .resting)
        HubRowFrame(state: state) {
            VStack(alignment: .leading, spacing: Space.n2) {
                HStack(spacing: Space.n4) {
                    SlotNumberLabel(number: slot.value)
                    SlotThumbnail(
                        record: record,
                        url: page.thumbnails[slot],
                        game: page.game,
                        isBusy: page.busy == slot
                    )
                    HubRowText(
                        label: rowLabel(record),
                        detail: detail(record)
                    )
                    Spacer(minLength: Space.n3)
                    if page.isJustSaved, page.savedSlot == slot {
                        SavedMark()
                    }
                }
                if isOpen {
                    buttons
                        .padding(.leading, Space.n6 + Space.n4)
                        .padding(.top, Space.n2)
                        .padding(.bottom, Space.n1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(record))
        .accessibilityAddTraits(.isButton)
    }

    private var buttons: some View {
        HStack(spacing: Space.n4) {
            HubInlineButton(
                glyph: "clock.arrow.circlepath",
                label: "Load",
                isHighlighted: page.choice == .load,
                confirmGlyph: confirmGlyph
            )
            HubInlineButton(
                glyph: "square.and.arrow.down",
                label: "Save Here",
                armedVerb: page.arming.isArmed(slot) ? "replace" : nil,
                isHighlighted: page.choice == .saveHere,
                confirmGlyph: confirmGlyph
            )
        }
    }

    private func rowLabel(_ record: SlotRecord?) -> String {
        if page.busy == slot, let busyLabel = page.busyLabel {
            return busyLabel
        }
        return record.map { HubFormat.sentenceDate($0.savedAt) } ?? "Empty"
    }

    private func detail(_ record: SlotRecord?) -> HubDetail {
        guard let record else { return .text("Save this moment here") }
        return record.hasThumbnail ? .none : .text("Gets a picture the first time you load it")
    }

    private func label(_ record: SlotRecord?) -> String {
        guard let record else { return "Slot \(slot.value), empty" }
        return "Slot \(slot.value), \(HubFormat.date(record.savedAt))"
    }
}

private struct SlotNumberLabel: View {
    let number: Int

    @Environment(\.isHubRowInverted) private var isInverted

    var body: some View {
        Text("\(number)")
            .typeStyle(TypeStyle.titleS.digits)
            .foregroundStyle(isInverted ? Palette.actionText : Palette.textSecondary)
            .frame(width: Space.n6)
    }
}

private struct SavedMark: View {
    @Environment(\.isHubRowInverted) private var isInverted

    var body: some View {
        HStack(spacing: Space.n2) {
            GlyphLabel(
                symbol: "checkmark.circle.fill",
                size: Layout.glyphInline,
                color: isInverted ? Palette.actionText : Palette.success
            )
            Text("Saved")
                .typeStyle(.meta)
                .foregroundStyle(isInverted ? Palette.actionText : Palette.success)
        }
    }
}
