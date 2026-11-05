import SwiftUI

struct ActionButton: View {
    let glyph: String?
    let label: String
    var sublabel: String?
    var note: String?
    let isHighlighted: Bool
    var isBusy = false

    @AccessibilityFocusState private var isVoiceOverFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.n3) {
            face
            if let note {
                Text(note)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: Layout.noteMax, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, sublabel, note].compactMap(\.self).joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityFocused($isVoiceOverFocused)
        .onChange(of: isHighlighted) {
            if isHighlighted {
                isVoiceOverFocused = true
            }
        }
    }

    private var face: some View {
        HStack(spacing: Space.n4) {
            if isBusy {
                Spinner(onAction: true)
            } else if let glyph {
                GlyphLabel(symbol: glyph, size: Layout.glyphStatus, color: foreground)
            }
            VStack(alignment: .leading, spacing: Space.half) {
                Text(label)
                    .typeStyle(.headline)
                    .foregroundStyle(foreground)
                    .fixedSize()
                if let sublabel {
                    Text(sublabel)
                        .typeStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isHighlighted ? Palette.actionText : Palette.textSecondary)
                }
            }
        }
        .padding(.vertical, Space.n4)
        .padding(.leading, Space.n5)
        .padding(.trailing, Space.n6)
        .frame(minHeight: Layout.buttonMinHeight)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Palette.actionFill)
                    .shadow(color: Palette.actionFill.opacity(0.35), radius: 28)
            }
        }
        .glassSurface(in: RoundedRectangle(cornerRadius: Radius.control), isInteractive: true)
        .opacity(isHighlighted ? 1 : 0.92)
        .scaleEffect(isHighlighted ? 1 : 0.97, anchor: .leading)
        .animation(Motion.easeOut(Motion.focus), value: isHighlighted)
    }

    private var foreground: Color {
        isHighlighted ? Palette.actionText : Palette.textPrimary
    }
}

struct ButtonGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.n5) { content }
            VStack(alignment: .leading, spacing: Space.n5) { content }
        }
    }
}
