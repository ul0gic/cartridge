import SwiftUI

enum MessageKind {
    case warning
    case danger
    case success

    var symbol: String {
        switch self {
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .warning: Palette.warning
        case .danger: Palette.danger
        case .success: Palette.success
        }
    }
}

struct MessageHead: View {
    let kind: MessageKind
    let text: String

    var body: some View {
        HStack(spacing: Space.n3) {
            GlyphLabel(symbol: kind.symbol, size: Layout.glyphMessage, color: kind.tint)
            Text(text)
                .typeStyle(.titleS)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.bottom, Space.n3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct MessageParagraph: View {
    let text: String
    var isFullPage = false

    var body: some View {
        Text(text)
            .typeStyle(isFullPage ? .lede : .body)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: Layout.measure, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FileChip: View {
    let name: String
    let region: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .typeStyle(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
            Text(region)
                .typeStyle(.meta)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, Space.n2)
        .padding(.horizontal, Space.n4)
        .controlPlate()
        .accessibilityElement(children: .combine)
    }
}

struct InlineResult: View {
    let kind: MessageKind
    let lead: String
    let rest: String

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: Space.n2) {
            GlyphLabel(symbol: kind.symbol, color: kind.tint)
            Text("\(Text(lead).fontWeight(.semibold)) \(rest)")
                .typeStyle(.meta)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n4)
        .frame(maxWidth: Layout.measure, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityElement(children: .combine)
        .onAppear {
            AccessibilityNotification.Announcement("\(lead) \(rest)").post()
        }
    }

    private var fill: Color {
        switch kind {
        case .warning: Palette.bandWarningFill
        case .danger: Palette.bandDangerFill
        case .success: Palette.controlFill
        }
    }
}
