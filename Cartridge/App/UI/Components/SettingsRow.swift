import SwiftUI

enum SettingsRowState {
    case resting
    case highlighted
    case info
    case disabled
}

enum SettingsGlyph {
    case symbol(String)
    case noController
}

enum SettingsAccessory {
    case none
    case success
    case spinner
}

struct SettingsStatus: Identifiable {
    let text: String
    let isReady: Bool

    var id: String {
        text
    }
}

enum SettingsTrailing {
    case none
    case text(String)
    case chevron
}

struct SettingsRow: View {
    let glyph: SettingsGlyph
    let label: String
    let detail: String?
    var statuses: [SettingsStatus] = []
    var accessory = SettingsAccessory.none
    var trailing = SettingsTrailing.none
    let state: SettingsRowState

    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var isVoiceOverFocused: Bool

    var body: some View {
        HStack(spacing: Space.n4) {
            glyphView
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .typeStyle(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(primary)
                if !statuses.isEmpty {
                    statusesView
                } else if let detail {
                    HStack(spacing: Space.n2) {
                        accessoryView
                        Text(detail)
                            .typeStyle(.meta)
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: Space.n4)
            trailingView
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n5)
        .frame(minHeight: Layout.rowMinHeight)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay { outline }
        .focusRing(state == .highlighted, radius: Radius.control)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(state == .info ? [] : .isButton)
        .accessibilityFocused($isVoiceOverFocused)
        .onChange(of: state) {
            if state == .highlighted {
                isVoiceOverFocused = true
            }
        }
    }

    @ViewBuilder private var glyphView: some View {
        switch glyph {
        case .symbol(let name): GlyphLabel(symbol: name, size: Layout.glyphStatus, color: primary)
        case .noController: NoControllerGlyph().foregroundStyle(primary)
        }
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .none: EmptyView()
        case .success: GlyphLabel(symbol: "checkmark.circle.fill", color: Palette.success)
        case .spinner: Spinner(onAction: state == .highlighted)
        }
    }

    private var statusesView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.n5) { statusItems }
            VStack(alignment: .leading, spacing: Space.n1) { statusItems }
        }
    }

    private var statusItems: some View {
        ForEach(statuses) { status in
            HStack(spacing: Space.n2) {
                GlyphLabel(
                    symbol: status.isReady ? "checkmark.circle.fill" : "circle.dashed",
                    color: statusColor(status)
                )
                Text(status.text)
                    .typeStyle(.meta)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
        }
    }

    private func statusColor(_ status: SettingsStatus) -> Color {
        if state == .highlighted {
            return Palette.actionText
        }
        return status.isReady ? Palette.success : Palette.textSecondary
    }

    @ViewBuilder private var trailingView: some View {
        switch trailing {
        case .none: EmptyView()
        case .text(let text): Text(text).typeStyle(.body).foregroundStyle(secondary)
        case .chevron: GlyphLabel(symbol: "chevron.right", size: Layout.glyphStatus, color: secondary)
        }
    }

    @ViewBuilder private var outline: some View {
        let stroke = contrast == .increased ? Palette.keycapStroke : Palette.controlStroke
        switch state {
        case .info, .disabled: RoundedRectangle(cornerRadius: Radius.control).strokeBorder(
                stroke,
                lineWidth: Layout.strokeHair
            )
        case .resting: RoundedRectangle(cornerRadius: Radius.control).strokeBorder(stroke, lineWidth: Layout.strokeHair)
        case .highlighted: EmptyView()
        }
    }

    private var fill: Color {
        switch state {
        case .highlighted: Palette.actionFill
        case .resting: Palette.controlFill
        case .info, .disabled: .clear
        }
    }

    private var primary: Color {
        switch state {
        case .highlighted: Palette.actionText
        case .disabled: Palette.textTertiary
        case .resting, .info: Palette.textPrimary
        }
    }

    private var secondary: Color {
        switch state {
        case .highlighted: Palette.actionText
        case .disabled: Palette.textTertiary
        case .resting, .info: Palette.textSecondary
        }
    }

    private var spokenLabel: String {
        let parts = [label, detail] + statuses.map(\.text) + [trailingSpoken]
        return parts.compactMap(\.self).joined(separator: ", ")
    }

    private var trailingSpoken: String? {
        switch trailing {
        case .text(let text): text
        case .none, .chevron: nil
        }
    }
}
