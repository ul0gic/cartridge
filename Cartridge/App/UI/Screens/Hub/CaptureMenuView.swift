import SwiftUI

struct CaptureMenuView: View {
    let model: AppModel
    let menu: CaptureMenuModel

    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chrome = model.chrome
        ZStack {
            Palette.scrimGame
            TopBar(controller: chrome.controller, showsWordmark: false, safeTop: chrome.safeTop)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Space.n1) {
                    Text("Capture")
                        .typeStyle(.titleM)
                        .foregroundStyle(Palette.textPrimary)
                    Text(menu.subtitle)
                        .typeStyle(.meta)
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.bottom, Space.n5)
                HStack(spacing: Space.n4) {
                    ForEach(menu.cards, id: \.self) { card in
                        CaptureCardView(
                            card: card,
                            isRecording: menu.recorder.isRecording,
                            isHighlighted: menu.highlighted == card
                        )
                    }
                }
                HintsRow(
                    hints: [
                        Hint(kind: .game, label: "Move"),
                        Hint(kind: .confirm, label: "Select"),
                        Hint(kind: .back, label: "Resume"),
                    ],
                    glyphs: chrome.glyphs
                )
                .padding(.top, Space.n5)
            }
            .padding(.top, Space.n6)
            .padding(.horizontal, Space.n7)
            .padding(.bottom, Space.n5)
            .hubPlate(radius: Radius.sheet)
            .shadow(color: Palette.shadowArt, radius: 35, x: 0, y: 30)
            .offset(y: isShown || reduceMotion ? 0 : Layout.sheetRise)
            .opacity(isShown ? 1 : 0)
            .padding(.bottom, Layout.sheetBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            withAnimation(Motion.easeOut(Motion.sheet)) { isShown = true }
            model.hubDidAppear()
        }
    }
}

private struct CaptureCardView: View {
    let card: CaptureCardID
    let isRecording: Bool
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlyphLabel(symbol: glyph, size: Layout.glyphCard, color: glyphColor)
            Spacer(minLength: 0)
            Text(label)
                .typeStyle(.headline)
                .foregroundStyle(foreground)
                .lineLimit(1)
            Text(subtitle)
                .typeStyle(.caption)
                .foregroundStyle(isHighlighted ? Palette.actionText : Palette.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .padding(Space.n4)
        .frame(width: Self.width, height: Layout.cardHeight, alignment: .leading)
        .background(
            isHighlighted ? Palette.actionFill : Palette.controlFill,
            in: RoundedRectangle(cornerRadius: Radius.control)
        )
        .scaleEffect(isHighlighted && !reduceMotion ? Layout.cardFocusScale : 1)
        .animation(Motion.easeOut(Motion.focus), value: isHighlighted)
        .zIndex(isHighlighted ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    private static let width: CGFloat = 280

    private var glyph: String {
        switch card {
        case .screenshot: "camera"
        case .recording: isRecording ? "stop.circle" : "record.circle"
        case .replay: "gobackward.30"
        }
    }

    private var label: String {
        switch card {
        case .screenshot: "Screenshot"
        case .recording: isRecording ? "Stop Recording" : "Start Recording"
        case .replay: "Save Last 30 Seconds"
        }
    }

    private var subtitle: String {
        switch card {
        case .screenshot: "Saves this picture to the Gallery"
        case .recording: isRecording ? "Saves the clip to the Gallery" : "Up to 30 minutes, until you stop"
        case .replay: "Saves what just happened"
        }
    }

    private var foreground: Color {
        isHighlighted ? Palette.actionText : Palette.textPrimary
    }

    private var glyphColor: Color {
        card == .recording && !isRecording && !isHighlighted ? Palette.danger : foreground
    }
}
