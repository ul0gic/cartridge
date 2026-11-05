import AppKit

enum TitleFitter {
    static func fit(_ title: String, width: CGFloat, style: TypeStyle) -> String {
        let font = style.appKitFont
        return title
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { truncate(String($0), to: width, font: font) }
            .joined(separator: " ")
    }

    private static func truncate(_ word: String, to width: CGFloat, font: NSFont) -> String {
        guard measure(word, font) > width else { return word }
        var characters = Array(word)
        while characters.count > 1 {
            characters.removeLast()
            let candidate = String(characters) + "…"
            if measure(candidate, font) <= width {
                return candidate
            }
        }
        return "…"
    }

    private static func measure(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
