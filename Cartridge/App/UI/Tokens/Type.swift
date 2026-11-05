import AppKit
import SwiftUI

extension Font.Width {
    static let narrowest = Font.Width(-0.5) // wdth 56 axis minimum; .compressed (-0.3) stops short
}

struct TypeStyle: Sendable {
    let size: CGFloat
    let weight: Font.Weight
    let width: Font.Width?
    let leading: CGFloat
    let tracking: CGFloat
    var monospacedDigits = false

    var font: Font {
        let base = Font.system(size: size, weight: weight)
        return monospacedDigits ? base.monospacedDigit() : base
    }

    var lineSpacing: CGFloat {
        size * leading - NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: size))
    }

    var appKitFont: NSFont {
        let weight: NSFont.Weight = switch self.weight {
        case .heavy: .heavy
        case .bold: .bold
        case .semibold: .semibold
        default: .regular
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let width else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.width: width.value]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    var digits: TypeStyle {
        var style = self
        style.monospacedDigits = true
        return style
    }

    static let display = TypeStyle(size: 120, weight: .heavy, width: .condensed, leading: 0.9, tracking: -0.02)
    static let titleXL = TypeStyle(size: 80, weight: .heavy, width: .condensed, leading: 0.94, tracking: -0.01)
    static let titleXLLong = TypeStyle(size: 64, weight: .heavy, width: .condensed, leading: 0.94, tracking: -0.01)
    static let titleL = TypeStyle(size: 56, weight: .heavy, width: .condensed, leading: 0.94, tracking: -0.01)
    static let titleLLong = TypeStyle(size: 44, weight: .heavy, width: .condensed, leading: 0.94, tracking: -0.01)
    static let launchWordmark = TypeStyle(size: 56, weight: .heavy, width: .condensed, leading: 0.94, tracking: -0.02)
    static let titleM = TypeStyle(size: 36, weight: .heavy, width: .condensed, leading: 1.0, tracking: 0)
    static let titleS = TypeStyle(size: 28, weight: .bold, width: nil, leading: 1.2, tracking: 0)
    static let topbarWordmark = TypeStyle(size: 28, weight: .heavy, width: .condensed, leading: 1.2, tracking: -0.01)
    static let lede = TypeStyle(size: 26, weight: .regular, width: nil, leading: 1.36, tracking: 0)
    static let headline = TypeStyle(size: 24, weight: .bold, width: nil, leading: 1.2, tracking: 0)
    static let rail = TypeStyle(size: 22, weight: .regular, width: nil, leading: 1.18, tracking: 0)
    static let body = TypeStyle(size: 21, weight: .regular, width: nil, leading: 1.36, tracking: 0)
    static let hint = TypeStyle(size: 20, weight: .regular, width: nil, leading: 1.2, tracking: 0)
    static let tile = TypeStyle(size: 20, weight: .heavy, width: .narrowest, leading: 1.0, tracking: 0)
    static let meta = TypeStyle(size: 18, weight: .regular, width: nil, leading: 1.36, tracking: 0)
    static let caption = TypeStyle(size: 16, weight: .regular, width: nil, leading: 1.36, tracking: 0)
    static let keycap = TypeStyle(size: 15, weight: .semibold, width: nil, leading: 1.0, tracking: 0)
    static let tileSystem = TypeStyle(size: 14, weight: .bold, width: nil, leading: 1.36, tracking: 0)

    static func title(long: Bool, large: Bool) -> TypeStyle {
        switch (large, long) {
        case (true, true): .titleXLLong
        case (true, false): .titleXL
        case (false, true): .titleLLong
        case (false, false): .titleL
        }
    }
}

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .fontWidth(style.width)
            .tracking(style.tracking * style.size)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}

extension String {
    var isLongTitle: Bool {
        count > Layout.longTitleCharacters
    }
}
