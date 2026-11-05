import SwiftUI

struct SlotThumbnail: View {
    let record: SlotRecord?
    let url: URL?
    let game: GameRecord
    let isBusy: Bool

    @Environment(\.isHubRowInverted) private var isInverted
    @State private var image: CGImage?

    var body: some View {
        content
            .frame(width: HubStyle.slotThumbHeight * HubStyle.screenRatio, height: HubStyle.slotThumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
            .task(id: LoadKey(url: url, savedAt: record?.savedAt)) {
                image = if let url {
                    await HubImage.load(url)
                } else {
                    nil
                }
            }
    }

    @ViewBuilder private var content: some View {
        if isBusy {
            Spinner(onAction: isInverted)
        } else if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
        } else if record != nil {
            let stops = Palette.placeholder(PlaceholderPalette.index(for: game.title))
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [stops.top, stops.middle, stops.bottom], startPoint: .top, endPoint: .bottom)
                Text("No picture yet")
                    .typeStyle(.tileSystem)
                    .foregroundStyle(Palette.textOnArt)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, Space.n1)
                    .padding(.vertical, Space.half)
                    .frame(maxWidth: .infinity)
                    .background(Palette.artScrim)
            }
        } else {
            RoundedRectangle(cornerRadius: Radius.thumb)
                .strokeBorder(isInverted ? Palette.actionText : Palette.controlStroke, lineWidth: Layout.strokeHair)
                .overlay {
                    GlyphLabel(
                        symbol: "plus",
                        size: Layout.glyphInline,
                        color: isInverted ? Palette.actionText : Palette.textSecondary
                    )
                }
        }
    }

    private struct LoadKey: Hashable {
        let url: URL?
        let savedAt: Date?
    }
}
