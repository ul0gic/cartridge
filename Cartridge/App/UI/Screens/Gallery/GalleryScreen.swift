import SwiftUI

struct GalleryScreen: View {
    let model: AppModel

    var body: some View {
        ZStack {
            GalleryBrowser(model: model)
            if let viewer = model.shell.gallery.viewer {
                GalleryViewer(viewer: viewer, store: model.dependencies.gallery, chrome: model.chrome)
            }
        }
    }
}

private struct GalleryBrowser: View {
    let model: AppModel

    @State private var backdrop: GalleryThumbnail?

    var body: some View {
        let store = model.dependencies.gallery
        let items = store.items
        let index = min(model.shell.gallery.index, max(0, items.count - 1))
        let highlighted = items.indices.contains(index) ? items[index] : nil
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: hints(isEmpty: items.isEmpty),
            counter: items.isEmpty ? nil : "\(index + 1) of \(items.count)",
            bar: model.shellBar,
            backdrop: {
                if let backdrop {
                    GalleryBackdrop(thumbnail: backdrop)
                } else {
                    CinematicBackdrop(source: .collage, style: .detail, heightFraction: 1)
                }
            },
            content: {
                if items.isEmpty {
                    EmptyGallery(topInset: model.contentTop)
                } else {
                    GalleryGrid(
                        store: store,
                        focused: model.shell.barFocus == nil ? index : nil,
                        animatesScroll: model.animatesScroll
                    ) { model.shell.gallery.columns = $0 }
                        .padding(.horizontal, Layout.marginX)
                        .padding(.top, model.contentTop)
                        .padding(.bottom, Layout.hintbarHeight)
                }
            }
        )
        .task(id: highlighted?.id) {
            guard let highlighted else {
                backdrop = nil
                return
            }
            backdrop = await GalleryThumbnails.load(store.url(of: highlighted), kind: highlighted.kind)
        }
    }

    private func hints(isEmpty: Bool) -> [Hint] {
        model.shellHints(
            isEmpty
                ? [Hint(kind: .back, label: "Menu")]
                : [
                    Hint(kind: .move, label: "Move"),
                    Hint(kind: .confirm, label: "Open"),
                    Hint(kind: .back, label: "Menu"),
                ]
        )
    }
}

private struct GalleryBackdrop: View {
    let thumbnail: GalleryThumbnail

    private static let dim = 0.85

    var body: some View {
        let key = ObjectIdentifier(thumbnail)
        ZStack {
            GeometryReader { proxy in
                Image(decorative: thumbnail.image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: Layout.backdropBlurHeavy)
                    .scaleEffect(Layout.focusScale)
                    .clipped()
            }
            .overlay { Palette.background.opacity(Self.dim) }
            .id(key)
            .transition(.opacity)
        }
        .animation(Motion.easeInOut(Motion.ambient).delay(Motion.ambientDelay.seconds), value: key)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EmptyGallery: View {
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: Space.n4) {
            Image(systemName: "photo.stack")
                .font(.system(size: Layout.galleryGlyph, weight: .light))
                .foregroundStyle(Palette.textPrimary)
                .padding(Space.n6)
                .glassSurface(in: Circle())
            Text("Your gallery is empty")
                .typeStyle(.titleM)
                .foregroundStyle(Palette.textPrimary)
            Text("Screenshots and clips you capture while playing will show up here.")
                .typeStyle(.lede)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Layout.measure)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, topInset)
        .padding(.bottom, Layout.hintbarHeight)
    }
}
