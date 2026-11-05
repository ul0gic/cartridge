import SwiftUI

enum HubRowState {
    case resting
    case highlighted
    case disabled
    case open
}

enum HubDetail {
    case none
    case text(String)
    case success(String)
    case armed(verb: String)
}

struct HubRowFrame<Content: View>: View {
    let state: HubRowState
    var padding = EdgeInsets(top: Space.n3, leading: Space.n5, bottom: Space.n3, trailing: Space.n5)
    @ViewBuilder let content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        content
            .environment(\.isHubRowInverted, state == .highlighted)
            .environment(\.isHubRowDisabled, state == .disabled)
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: Layout.rowMinHeight, alignment: .leading)
            .background(state == .resting || state == .highlighted ? fill : .clear, in: shape)
            .overlay { outline(shape) }
            .focusRing(state == .highlighted, radius: Radius.control)
    }

    private var disabledStroke: Color {
        contrast == .increased ? Palette.keycapStroke : Palette.controlStroke
    }

    private var fill: Color {
        state == .highlighted ? Palette.actionFill : Palette.controlFill
    }

    @ViewBuilder
    private func outline(_ shape: RoundedRectangle) -> some View {
        switch state {
        case .disabled:
            shape.strokeBorder(disabledStroke, lineWidth: Layout.strokeHair)
        case .open:
            shape.strokeBorder(Palette.keycapStroke, lineWidth: Layout.strokeHair)
        case .resting, .highlighted:
            EmptyView()
        }
    }
}

struct HubRowText: View {
    let label: String
    var labelLines = 1
    var labelStyle = TypeStyle.headline
    var detail = HubDetail.none
    var confirmGlyph: String?

    @Environment(\.isHubRowInverted) private var isInverted
    @Environment(\.isHubRowDisabled) private var isDisabled

    var body: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(label)
                .typeStyle(labelStyle)
                .fontWeight(.semibold)
                .foregroundStyle(labelColor)
                .lineLimit(labelLines)
                .multilineTextAlignment(.leading)
            detailView
        }
    }

    private var labelColor: Color {
        if isInverted {
            return Palette.actionText
        }
        return isDisabled ? Palette.textSecondary : Palette.textPrimary
    }

    @ViewBuilder private var detailView: some View {
        switch detail {
        case .none:
            EmptyView()
        case .text(let text):
            Text(text)
                .typeStyle(.meta)
                .foregroundStyle(isInverted ? Palette.actionText : Palette.textSecondary)
                .lineLimit(1)
        case .success(let text):
            Text(text)
                .typeStyle(.meta)
                .foregroundStyle(isInverted ? Palette.actionText : Palette.success)
                .lineLimit(1)
        case .armed(let verb):
            ArmedText(verb: verb, confirmGlyph: confirmGlyph)
                .typeStyle(.meta)
                .foregroundStyle(isInverted ? Palette.actionText : Palette.textSecondary)
                .lineLimit(1)
        }
    }
}

struct HubSwitch: View {
    let isOn: Bool

    @Environment(\.isHubRowInverted) private var isInverted

    var body: some View {
        let inset = (HubStyle.switchHeight - HubStyle.switchKnob) / 2
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? track : .clear)
                .overlay {
                    Capsule().strokeBorder(isOn ? .clear : outline, lineWidth: Layout.strokeKeycap)
                }
            Circle()
                .fill(knob)
                .frame(width: HubStyle.switchKnob, height: HubStyle.switchKnob)
                .padding(inset)
        }
        .frame(width: HubStyle.switchWidth, height: HubStyle.switchHeight)
        .accessibilityHidden(true)
    }

    private var track: Color {
        isInverted ? Palette.actionText : Palette.success
    }

    private var outline: Color {
        isInverted ? Palette.actionText : Palette.keycapStroke
    }

    private var knob: Color {
        switch (isOn, isInverted) {
        case (true, true): Palette.actionFill
        case (true, false): Palette.textOnArt
        case (false, true): Palette.actionText
        case (false, false): Palette.textSecondary
        }
    }
}

struct HubOnOff: View {
    let isOn: Bool

    @Environment(\.isHubRowInverted) private var isInverted

    var body: some View {
        HStack(spacing: Space.n3) {
            Text(isOn ? "On" : "Off")
                .typeStyle(.meta)
                .foregroundStyle(isInverted ? Palette.actionText : Palette.textSecondary)
            HubSwitch(isOn: isOn)
        }
    }
}

struct HubPill: View {
    let text: String

    @Environment(\.isHubRowInverted) private var isInverted

    private var outline: Color {
        isInverted ? Palette.actionText : Palette.controlStroke
    }

    var body: some View {
        Text(text)
            .typeStyle(.caption)
            .foregroundStyle(isInverted ? Palette.actionText : Palette.textSecondary)
            .padding(.horizontal, Space.n2)
            .padding(.vertical, Space.half)
            .overlay {
                Capsule().strokeBorder(outline, lineWidth: Layout.strokeHair)
            }
    }
}

struct HubSquareButton: View {
    let glyph: String
    let isHighlighted: Bool
    let isArmed: Bool
    let label: String

    private var plateFill: Color {
        isHighlighted ? Palette.actionFill : Palette.controlFill
    }

    var body: some View {
        GlyphLabel(
            symbol: isArmed ? "exclamationmark.triangle.fill" : glyph,
            size: Layout.glyphStatus,
            color: isHighlighted ? Palette.actionText : Palette.textPrimary
        )
        .frame(width: Layout.rowMinHeight, height: Layout.rowMinHeight)
        .background(plateFill, in: RoundedRectangle(cornerRadius: Radius.control))
        .focusRing(isHighlighted, radius: Radius.control)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

struct HubInlineButton: View {
    let glyph: String
    let label: String
    var armedVerb: String?
    let isHighlighted: Bool
    let confirmGlyph: String?

    var body: some View {
        HStack(spacing: Space.n3) {
            GlyphLabel(
                symbol: armedVerb == nil ? glyph : "exclamationmark.triangle.fill",
                size: Layout.glyphStatus,
                color: foreground
            )
            VStack(alignment: .leading, spacing: Space.half) {
                Text(label)
                    .typeStyle(.headline)
                    .foregroundStyle(foreground)
                if let armedVerb {
                    ArmedText(verb: armedVerb, confirmGlyph: confirmGlyph)
                        .typeStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(foreground)
                }
            }
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n5)
        .background(plateFill, in: RoundedRectangle(cornerRadius: Radius.control))
        .focusRing(isHighlighted, radius: Radius.control)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(armedVerb.map { "\(label), press again to \($0)" } ?? label)
        .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        isHighlighted ? Palette.actionText : Palette.textPrimary
    }

    private var plateFill: Color {
        isHighlighted ? Palette.actionFill : Palette.controlFill
    }
}
