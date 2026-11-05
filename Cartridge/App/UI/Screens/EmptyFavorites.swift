import SwiftUI

struct EmptyFavorites: View {
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: Space.n4) {
            Image(systemName: "heart")
                .font(.system(size: Layout.galleryGlyph, weight: .light))
                .foregroundStyle(Palette.textPrimary)
                .padding(Space.n6)
                .glassSurface(in: Circle())
            Text("No favorites yet")
                .typeStyle(.titleM)
                .foregroundStyle(Palette.textPrimary)
            Text("Press △ on a game to add it.")
                .typeStyle(.lede)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Layout.measure)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, topInset)
        .padding(.bottom, Layout.hintbarHeight)
        .accessibilityElement(children: .combine)
    }
}
