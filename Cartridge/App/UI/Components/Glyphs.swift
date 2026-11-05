import AppKit
import SwiftUI

struct NoControllerGlyph: View {
    var size = Layout.glyphStatus

    var body: some View {
        Image(systemName: "gamecontroller")
            .font(.system(size: size))
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .accessibilityHidden(true)
    }
}

struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        // applicationIconImage comes from the IconServices cache, which keeps a replaced icon for the same bundle path
        Image(nsImage: Bundle.main.image(forResource: "AppIcon") ?? NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GlyphLabel: View {
    let symbol: String
    var size = Layout.glyphInline
    var color = Palette.textPrimary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
