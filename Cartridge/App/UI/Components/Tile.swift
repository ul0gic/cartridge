import SwiftUI

enum PlaceholderPalette {
    static func index(for title: String) -> Int {
        let hash = title.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return Int(hash % UInt32(Palette.placeholderCount)) + 1
    }
}

struct Tile: View {
    let title: String
    let system: GameSystem
    let art: TileArt
    let identifyingFileName: String?
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isVoiceOverFocused: Bool

    var body: some View {
        content
            .frame(width: Layout.tileWidth(for: system.tileAspect), height: Layout.tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile))
            .focusRing(isHighlighted, radius: Radius.tile)
            .shadow(
                color: isHighlighted ? Palette.shadowLift : .clear,
                radius: Layout.shadowLiftBlur / 2,
                x: 0,
                y: Layout.shadowLiftOffset
            )
            .scaleEffect(isHighlighted && !reduceMotion ? Layout.focusScale : 1)
            .animation(Motion.easeOut(Motion.focus), value: isHighlighted)
            .zIndex(isHighlighted ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens the game")
            .accessibilityAddTraits(.isButton)
            .accessibilityFocused($isVoiceOverFocused)
            .onChange(of: isHighlighted) {
                if isHighlighted {
                    isVoiceOverFocused = true
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let identifyingFileName {
            LoadingFace {
                Text(identifyingFileName.map(String.init).joined(separator: "\u{200B}"))
                    .typeStyle(TypeStyle.tileSystem)
                    .fontWeight(.regular)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            ArtFace(title: title, system: system, art: art, style: .tile)
        }
    }

    private var accessibilityLabel: String {
        if let identifyingFileName {
            return "Identifying \(identifyingFileName)"
        }
        return "\(title), \(system.displayName)"
    }
}
