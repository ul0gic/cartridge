import AppKit
import AVFoundation
import SwiftUI

struct GalleryViewer: View {
    let viewer: GalleryViewerModel
    let store: GalleryStore
    let chrome: ChromeState

    var body: some View {
        ZStack {
            Palette.playBackground
            picture
            StatusChip(controller: chrome.controller)
                .padding(.trailing, Layout.marginX)
                .padding(.top, chrome.safeTop + Space.n2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            Group {
                TitlePlate(item: viewer.item)
                    .frame(maxWidth: Layout.panelBodyMax, alignment: .leading)
                    .padding(.leading, Layout.sheetInsetX)
                    .padding(.top, chrome.safeTop + Space.n5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                ViewerBar(viewer: viewer, chrome: chrome)
                    .padding(.horizontal, Layout.sheetInsetX)
                    .padding(.bottom, Layout.sheetBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .opacity(viewer.platesVisible ? 1 : 0)
            .animation(Motion.easeInOut(Motion.handover), value: viewer.platesVisible)
        }
        .ignoresSafeArea()
        .onDisappear { viewer.stop() }
    }

    @ViewBuilder private var picture: some View {
        if let player = viewer.player {
            ClipSurface(player: player.player)
        } else if !viewer.isMissing {
            switch viewer.item.kind {
            case .gif: GIFSurface(url: store.url(of: viewer.item))
            case .screenshot, .clip: ScreenshotSurface(url: store.url(of: viewer.item))
            }
        }
    }
}

private struct ScreenshotSurface: View {
    let url: URL

    @State private var art: LoadedArt?

    var body: some View {
        ZStack {
            if let art {
                Image(decorative: art.image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { art = await ArtDecoder.load(url) }
    }
}

private final class GIFImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private struct GIFSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> GIFImageView {
        let view = GIFImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.animates = true
        view.image = NSImage(contentsOf: url)
        return view
    }

    func updateNSView(_ view: GIFImageView, context: Context) {}
}

private final class PlayerHostView: NSView {
    var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        return layer
    }
}

private struct ClipSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.wantsLayer = true
        view.playerLayer?.player = player
        return view
    }

    func updateNSView(_ view: PlayerHostView, context: Context) {}
}

private struct TitlePlate: View {
    let item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.n1) {
            Text(item.gameTitle)
                .typeStyle(.titleM)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(item.viewerLine)
                .typeStyle(.meta)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, Space.n4)
        .padding(.horizontal, Space.n5)
        .hubPlate(radius: Radius.control)
        .accessibilityElement(children: .combine)
    }
}

private struct ViewerBar: View {
    let viewer: GalleryViewerModel
    let chrome: ChromeState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.n4) {
            if let player = viewer.player {
                ClipProgress(player: player)
            }
            HStack(alignment: .top, spacing: Space.n5) {
                ForEach(Array(viewer.buttons.enumerated()), id: \.offset) { index, button in
                    ViewerButton(viewer: viewer, button: button, isHighlighted: index == viewer.focus, chrome: chrome)
                }
                Spacer(minLength: Space.n5)
                if let message = viewer.message {
                    ViewerMessageView(message: message)
                }
            }
            HintsRow(
                hints: [
                    Hint(kind: .move, label: "Move"),
                    Hint(kind: .confirm, label: "Select"),
                    Hint(kind: .back, label: "Gallery"),
                ],
                glyphs: chrome.glyphs
            )
        }
        .padding(.vertical, Space.n5)
        .padding(.horizontal, Space.n6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubPlate(radius: Radius.sheet)
    }
}

private struct ClipProgress: View {
    let player: ClipPlayer

    var body: some View {
        HStack(spacing: Space.n4) {
            Text(Self.text(player.elapsed))
            Capsule()
                .fill(Palette.controlFill)
                .frame(width: Layout.progressWidth, height: Layout.progressHeight)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Palette.focusRing)
                        .frame(width: Layout.progressWidth * player.fraction)
                }
            Text(Self.text(player.total))
        }
        .typeStyle(TypeStyle.meta.digits)
        .foregroundStyle(Palette.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.text(player.elapsed)) of \(Self.text(player.total))")
    }

    private static func text(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ViewerButton: View {
    let viewer: GalleryViewerModel
    let button: GalleryViewerModel.Button
    let isHighlighted: Bool
    let chrome: ChromeState

    var body: some View {
        switch button {
        case .playPause:
            let isPlaying = viewer.player?.isPlaying == true
            ActionButton(
                glyph: isPlaying ? "pause.fill" : "play.fill",
                label: isPlaying ? "Pause" : "Play",
                isHighlighted: isHighlighted
            )
        case .makeGIF:
            ActionButton(
                glyph: "photo.stack",
                label: viewer.isMakingGIF ? "Making GIF…" : "Make GIF",
                sublabel: viewer.isMakingGIF ? viewer.gifEstimate : nil,
                isHighlighted: isHighlighted,
                isBusy: viewer.isMakingGIF
            )
        case .showInFinder:
            ActionButton(glyph: "folder", label: "Show in Finder", isHighlighted: isHighlighted)
        case .delete:
            ActionButton(
                glyph: viewer.isDeleteArmed ? "exclamationmark.triangle.fill" : "trash",
                label: "Delete",
                sublabel: viewer.isDeleteArmed ? "Press \(chrome.glyphs == nil ? "Return" : "⊗") again to delete" : nil,
                isHighlighted: isHighlighted
            )
        }
    }
}

private struct ViewerMessageView: View {
    let message: ViewerMessage

    var body: some View {
        HStack(alignment: .top, spacing: Space.n3) {
            GlyphLabel(symbol: symbol, size: Layout.glyphStatus, color: tint)
            VStack(alignment: .leading, spacing: Space.n1) {
                Text(message.head)
                    .typeStyle(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                if let detail = message.detail {
                    Text(detail)
                        .typeStyle(.meta)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Space.n3)
        .padding(.horizontal, Space.n4)
        .frame(width: Layout.messageWidth, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityElement(children: .combine)
        .onAppear {
            AccessibilityNotification
                .Announcement([message.head, message.detail].compactMap(\.self).joined(separator: ". "))
                .post()
        }
    }

    private var symbol: String {
        switch message.kind {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch message.kind {
        case .ok: Palette.success
        case .warning: Palette.warning
        case .danger: Palette.danger
        }
    }

    private var fill: Color {
        switch message.kind {
        case .ok: Palette.controlFill
        case .warning: Palette.bandWarningFill
        case .danger: Palette.bandDangerFill
        }
    }
}
