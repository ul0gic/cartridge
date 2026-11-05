import AppKit
import ImageIO
import SwiftUI

enum HubStyle {
    static let columnWidth: CGFloat = 640
    static let cardHeight: CGFloat = 104
    static let slotThumbHeight: CGFloat = 64
    static let lookPreviewHeight: CGFloat = 96
    static let switchWidth: CGFloat = 56
    static let switchHeight: CGFloat = 32
    static let switchKnob: CGFloat = 24
    static let screenRatio: CGFloat = 4.0 / 3.0
    static let cardSubtitleLines = 2
    static let alertHold = Duration.seconds(5)
    static let fadeHeight = Space.n7

    static let materialPlay = dynamicColor(
        dark: NSColor(red: 30 / 255, green: 32 / 255, blue: 37 / 255, alpha: 0.90),
        light: NSColor(red: 250 / 255, green: 250 / 255, blue: 252 / 255, alpha: 0.90)
    )
    static let scrimPicture = dynamicColor(
        dark: NSColor(white: 0, alpha: 0.18),
        light: NSColor(white: 0, alpha: 0.10)
    )

    private static func dynamicColor(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum HubImage {
    @concurrent
    static func load(_ url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension EnvironmentValues {
    @Entry var isHubRowInverted = false
    @Entry var isHubRowDisabled = false
}

extension View {
    func hubPlate(radius: CGFloat) -> some View {
        glassSurface(in: RoundedRectangle(cornerRadius: radius), tint: HubStyle.materialPlay)
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Palette.materialStroke, lineWidth: Layout.strokeHair)
            }
    }
}
