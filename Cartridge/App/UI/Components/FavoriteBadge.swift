import SwiftUI

struct FavoriteBadge: View {
    private static let pop = Animation.spring(response: 0.32, dampingFraction: 0.62)

    let isFavorite: Bool

    var body: some View {
        ZStack {
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: Layout.glyphInline, weight: .semibold))
                    .foregroundStyle(.pink)
                    .padding(Space.n2)
                    .glassSurface(in: Circle())
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .accessibilityLabel("Favorite")
            }
        }
        .animation(Self.pop, value: isFavorite)
    }
}
