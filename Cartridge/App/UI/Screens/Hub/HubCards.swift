import SwiftUI

struct ArmedText: View {
    let verb: String
    let confirmGlyph: String?

    var body: some View {
        if let confirmGlyph {
            Text("Press \(Image(systemName: confirmGlyph)) again to \(verb)")
        } else {
            Text("Press Return again to \(verb)")
        }
    }
}

struct HubCardView: View {
    let card: HubCard
    let isHighlighted: Bool
    let confirmGlyph: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Space.n4) {
            glyph
                .frame(width: Layout.glyphCard, height: Layout.glyphCard)
            VStack(alignment: .leading, spacing: Space.half) {
                Text(card.label)
                    .typeStyle(.headline)
                    .foregroundStyle(primary)
                    .lineLimit(1)
                status
            }
            Spacer(minLength: 0)
        }
        .padding(Space.n4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: HubStyle.cardHeight)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay { outline }
        .scaleEffect(isInverted && !reduceMotion ? Layout.cardFocusScale : 1)
        .animation(Motion.easeOut(Motion.focus), value: isInverted)
        .zIndex(isInverted ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.label), \(spokenStatus)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(card.isEnabled ? "" : "Dimmed")
    }

    @ViewBuilder private var glyph: some View {
        if card.state == .busy {
            Spinner(onAction: isInverted)
        } else {
            GlyphLabel(
                symbol: card.state == .armed ? "exclamationmark.triangle.fill" : card.glyph,
                size: Layout.glyphCard,
                color: primary
            )
        }
    }

    private var status: some View {
        Group {
            switch card.status {
            case .text(let text): Text(text)
            case .armed(let verb): ArmedText(verb: verb, confirmGlyph: confirmGlyph)
            }
        }
        .typeStyle(.caption)
        .foregroundStyle(secondary)
        .lineLimit(HubStyle.cardSubtitleLines)
        .multilineTextAlignment(.leading)
    }

    private var spokenStatus: String {
        switch card.status {
        case .text(let text): text
        case .armed(let verb): "Press again to \(verb)"
        }
    }

    private var isInverted: Bool {
        isHighlighted && card.isEnabled
    }

    private var primary: Color {
        if !card.isEnabled {
            return Palette.textSecondary
        }
        return isInverted ? Palette.actionText : Palette.textPrimary
    }

    private var secondary: Color {
        isInverted ? Palette.actionText : Palette.textSecondary
    }

    private var fill: Color {
        if !card.isEnabled {
            return .clear
        }
        return isInverted ? Palette.actionFill : Palette.controlFill
    }

    @ViewBuilder private var outline: some View {
        if !card.isEnabled {
            RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(
                    contrast == .increased ? Palette.keycapStroke : Palette.controlStroke,
                    lineWidth: Layout.strokeHair
                )
        }
    }
}

struct HubMessageView: View {
    let message: HubMessage

    var body: some View {
        HStack(alignment: .top, spacing: Space.n3) {
            glyph
            VStack(alignment: .leading, spacing: Space.n1) {
                Text(message.head)
                    .typeStyle(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                if let detail = message.detail {
                    Text(detail)
                        .typeStyle(.meta)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n4)
        .frame(width: Layout.messageWidth, alignment: .leading)
        .modifier(MessagePlate(kind: message.kind))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var glyph: some View {
        if message.showsSpinner {
            Spinner()
                .frame(width: Layout.glyphStatus, height: Layout.glyphStatus)
        } else if message.showsNoController {
            NoControllerGlyph().foregroundStyle(tint)
        } else {
            GlyphLabel(symbol: message.glyph ?? defaultGlyph, size: Layout.glyphStatus, color: tint)
        }
    }

    private var defaultGlyph: String {
        switch message.kind {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch message.kind {
        case .ok: Palette.success
        case .info: Palette.textPrimary
        case .warn: Palette.warning
        case .danger: Palette.danger
        }
    }
}

private struct MessagePlate: ViewModifier {
    let kind: HubMessageKind

    func body(content: Content) -> some View {
        switch kind {
        case .ok, .info:
            content.hubPlate(radius: Radius.control)
        case .warn:
            content.background(Palette.bandWarningFill, in: RoundedRectangle(cornerRadius: Radius.control))
        case .danger:
            content.background(Palette.bandDangerFill, in: RoundedRectangle(cornerRadius: Radius.control))
        }
    }
}

struct HubMessageStack: View {
    let messages: [HubMessage]

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.n2) {
            ForEach(Array(messages.enumerated().reversed()), id: \.offset) { entry in
                HubMessageView(message: entry.element)
            }
        }
    }
}
