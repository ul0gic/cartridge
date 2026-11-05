import SwiftUI

struct PanelSlotPicker: View {
    private static let cardWidth: CGFloat = 280
    private static let cardsBeforeHighlight = 1

    let game: GameRecord
    let slots: [PanelSlot]
    let highlighted: SlotNumber?
    let isStarting: Bool
    let press: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            strip
            Text("Starts from this save. Your resume point is replaced when you next quit.")
                .typeStyle(.caption)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: Layout.panelNoteWidth, minHeight: Layout.panelNoteMinHeight, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.n4)
        }
    }

    private var strip: some View {
        let step = Self.cardWidth + Space.n4
        let visible = max(1, Int((Layout.panelBodyWidth + Space.n4) / step))
        let index = slots.firstIndex { $0.record.number == highlighted } ?? 0
        let first = max(0, min(index - Self.cardsBeforeHighlight, slots.count - visible))
        return HStack(alignment: .top, spacing: Space.n4) {
            ForEach(slots, id: \.record.number) { slot in
                let isHighlighted = slot.record.number == highlighted
                PanelSlotCard(
                    game: game,
                    slot: slot,
                    isHighlighted: isHighlighted,
                    isBusy: isStarting && isHighlighted
                )
                .frame(width: Self.cardWidth)
                .scaleEffect(isHighlighted ? press : 1)
            }
        }
        .fixedSize()
        .padding(Layout.focusBleed)
        .offset(x: -CGFloat(first) * step)
        .animation(reduceMotion ? nil : Motion.easeOut(Motion.scroll), value: first)
        .frame(width: Layout.panelBodyWidth + Layout.focusBleed * 2, alignment: .leading)
        .mask { fade(before: first > 0, after: first + visible < slots.count) }
        .padding(-Layout.focusBleed)
    }

    private func fade(before: Bool, after: Bool) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [before ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Layout.focusBleed)
            Color.black
            LinearGradient(colors: [.black, after ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Layout.focusBleed * 2)
        }
    }
}

private struct PanelSlotCard: View {
    let game: GameRecord
    let slot: PanelSlot
    let isHighlighted: Bool
    let isBusy: Bool

    @AccessibilityFocusState private var isVoiceOverFocused: Bool

    var body: some View {
        HubRowFrame(state: isHighlighted ? .highlighted : .resting) {
            HStack(spacing: Space.n4) {
                SlotThumbnail(record: slot.record, url: slot.thumbnail, game: game, isBusy: isBusy)
                PanelSlotText(
                    label: "Slot \(slot.record.number.value)",
                    date: HubFormat.sentenceDate(slot.record.savedAt)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slot \(slot.record.number.value), \(HubFormat.date(slot.record.savedAt))")
        .accessibilityAddTraits(.isButton)
        .accessibilityFocused($isVoiceOverFocused)
        .onAppear {
            isVoiceOverFocused = isHighlighted
        }
        .onChange(of: isHighlighted) {
            if isHighlighted {
                isVoiceOverFocused = true
            }
        }
    }
}

private struct PanelSlotText: View {
    let label: String
    let date: String

    @Environment(\.isHubRowInverted) private var isInverted

    var body: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(label)
                .typeStyle(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(isInverted ? Palette.actionText : Palette.textPrimary)
                .lineLimit(1)
            Text(date)
                .typeStyle(.meta)
                .foregroundStyle(isInverted ? Palette.actionText : Palette.textSecondary)
                .lineLimit(2, reservesSpace: true)
        }
    }
}
