import SwiftUI

struct CodePadView: View {
    private static let visibleCodeCharacters = 60

    let page: CheatsPage
    let pad: CodePad

    var body: some View {
        VStack(alignment: .leading, spacing: Space.n4) {
            codeLine
            Text(page.formatGuide)
                .typeStyle(.meta)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            keys
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeLine: some View {
        HStack(alignment: .center, spacing: Space.n1) {
            if pad.code.isEmpty {
                Text("Type a code")
                    .typeStyle(.titleM)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text(visibleCode)
                    .typeStyle(TypeStyle.titleM.digits)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
            }
            Capsule()
                .fill(Palette.focusRing)
                .frame(width: Layout.caretWidth, height: Layout.caretHeight)
        }
        .frame(minHeight: Layout.buttonMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.code.isEmpty ? "Code, empty" : "Code, \(pad.code)")
    }

    private var visibleCode: String {
        pad.code.count > Self.visibleCodeCharacters
            ? "…" + pad.code.suffix(Self.visibleCodeCharacters)
            : pad.code
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: Space.n2) {
            ForEach(Array(pad.rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: Space.n2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, key in
                        CodePadKeyView(key: key, isHighlighted: rowIndex == pad.row && columnIndex == pad.column)
                    }
                }
            }
        }
        .padding(Space.n4)
        .hubPlate(radius: Radius.art)
    }
}

private struct CodePadKeyView: View {
    let key: CodePadKey
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(label)
            .typeStyle(isWide ? .meta : .headline)
            .fontWeight(.bold)
            .foregroundStyle(isHighlighted ? Palette.actionText : Palette.textPrimary)
            .frame(width: isWide ? Layout.padKey * 2.5 : Layout.padKey, height: Layout.padKey)
            .background(
                isHighlighted ? Palette.actionFill : Palette.controlFill,
                in: RoundedRectangle(cornerRadius: Radius.keycap)
            )
            .scaleEffect(isHighlighted && !reduceMotion ? Layout.focusScale : 1)
            .animation(Motion.easeOut(Motion.focus), value: isHighlighted)
            .zIndex(isHighlighted ? 1 : 0)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private var isWide: Bool {
        switch key {
        case .character: false
        case .space, .delete, .add: true
        }
    }

    private var label: String {
        switch key {
        case .character(let character): String(character)
        case .space: "Space"
        case .delete: "Delete"
        case .add: "Add Code"
        }
    }
}
