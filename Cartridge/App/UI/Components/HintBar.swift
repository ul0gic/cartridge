import SwiftUI

enum HintKind {
    case move
    case game
    case row
    case confirm
    case back
    case options
    case secondary
    case sections
}

struct Hint: Identifiable, Equatable {
    let kind: HintKind
    let label: String

    var id: String {
        label
    }
}

struct HintGlyphs: Equatable {
    static let dpad = "dpad"

    let confirm: String
    let back: String
    let options: String
    let secondary: String
    let left: String
    let right: String
    let up: String
    let down: String
    let sectionLeft: String
    let sectionRight: String
}

struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .typeStyle(.keycap)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.n2)
            .frame(minWidth: Layout.keycapMinWidth, minHeight: Layout.keycapHeight)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.keycap)
                    .strokeBorder(Palette.keycapStroke, lineWidth: Layout.strokeKeycap)
            }
            .accessibilityHidden(true)
    }
}

struct HintBar: View {
    let hints: [Hint]
    let glyphs: HintGlyphs?
    let counter: String?

    var body: some View {
        HStack(spacing: Space.n6) {
            if !hints.isEmpty {
                HintsRow(hints: hints, glyphs: glyphs)
                    .padding(.horizontal, Space.n5)
                    .padding(.vertical, Space.n2)
                    .glassSurface(in: Capsule())
            }
            Spacer(minLength: Space.n6)
            if let counter {
                Text(counter)
                    .typeStyle(TypeStyle.hint.digits)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .padding(.horizontal, Layout.marginX)
        .frame(height: Layout.hintbarHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

struct HintsRow: View {
    let hints: [Hint]
    let glyphs: HintGlyphs?

    var body: some View {
        HStack(spacing: Space.n6) {
            ForEach(hints) { hint in
                HintView(hint: hint, glyphs: glyphs)
            }
        }
        .frame(minHeight: Layout.keycapHeight)
    }
}

private struct HintView: View {
    let hint: Hint
    let glyphs: HintGlyphs?

    var body: some View {
        HStack(spacing: Space.n2) {
            if let glyphs {
                ForEach(Self.symbols(for: hint.kind, in: glyphs), id: \.self) { symbol in
                    GlyphLabel(symbol: symbol, size: Layout.glyphHint)
                }
            } else {
                HStack(spacing: Space.n1) {
                    ForEach(Self.keys(for: hint.kind), id: \.self) { key in
                        Keycap(label: key)
                    }
                }
            }
            Text(hint.label)
                .typeStyle(.hint)
                .foregroundStyle(Palette.textSecondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.spoken(for: hint.kind, controller: glyphs != nil)): \(hint.label)")
    }

    private static func symbols(for kind: HintKind, in glyphs: HintGlyphs) -> [String] {
        switch kind {
        case .move: [HintGlyphs.dpad]
        case .game: [glyphs.left, glyphs.right]
        case .row: [glyphs.up, glyphs.down]
        case .confirm: [glyphs.confirm]
        case .back: [glyphs.back]
        case .options: [glyphs.options]
        case .secondary: [glyphs.secondary]
        case .sections: [glyphs.sectionLeft, glyphs.sectionRight]
        }
    }

    private static func keys(for kind: HintKind) -> [String] {
        switch kind {
        case .move: ["←", "→", "↑", "↓"]
        case .game: ["←", "→"]
        case .row: ["↑", "↓"]
        case .confirm: ["Return"]
        case .back: ["Esc"]
        case .options: ["⌘", ","]
        case .secondary: ["."]
        case .sections: ["Tab"]
        }
    }

    private static func spoken(for kind: HintKind, controller: Bool) -> String {
        controller ? spokenButton(for: kind) : spokenKey(for: kind)
    }

    private static func spokenButton(for kind: HintKind) -> String {
        switch kind {
        case .move, .game, .row: "Directional pad"
        case .confirm: "Cross button"
        case .back: "Circle button"
        case .options: "Options button"
        case .secondary: "Triangle button"
        case .sections: "L1 or R1"
        }
    }

    private static func spokenKey(for kind: HintKind) -> String {
        switch kind {
        case .move: "Arrow keys"
        case .game: "Left or right arrow"
        case .row: "Up or down arrow"
        case .confirm: "Return"
        case .back: "Escape"
        case .options: "Command comma"
        case .secondary: "Period"
        case .sections: "Tab"
        }
    }
}
