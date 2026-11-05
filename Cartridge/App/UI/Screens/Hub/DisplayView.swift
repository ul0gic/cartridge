import SwiftUI

struct DisplayView: View {
    let page: DisplayPage

    var body: some View {
        VStack(spacing: Space.n2) {
            ForEach(DisplayLook.allCases, id: \.self) { look in
                LookRow(page: page, look: look)
            }
        }
    }
}

private struct LookRow: View {
    let page: DisplayPage
    let look: DisplayLook

    var body: some View {
        let inUse = page.inUse == look
        HubRowFrame(
            state: page.highlighted == look ? .highlighted : .resting,
            padding: EdgeInsets(top: Space.n3, leading: Space.n3, bottom: Space.n3, trailing: Space.n5)
        ) {
            HStack(spacing: Space.n4) {
                LookPreview(image: page.preview, look: look)
                HubRowText(label: look.displayName, detail: .text(Self.line(for: look)))
                Spacer(minLength: Space.n3)
                if inUse {
                    InUseMark()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(look.displayName), \(Self.line(for: look))\(inUse ? ", in use" : "")")
        .accessibilityAddTraits(.isButton)
    }

    private static func line(for look: DisplayLook) -> String {
        switch look {
        case .original: "Every pixel as the console drew it"
        case .sharp: "Even pixels with soft edges"
        case .crt: "Scanlines and glow, like a tube TV"
        }
    }
}

private struct InUseMark: View {
    @Environment(\.isHubRowInverted) private var isInverted

    var body: some View {
        let color = isInverted ? Palette.actionText : Palette.success
        HStack(spacing: Space.n2) {
            GlyphLabel(symbol: "checkmark.circle.fill", size: Layout.glyphInline, color: color)
            Text("In use")
                .typeStyle(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

private struct LookPreview: View {
    let image: CGImage?
    let look: DisplayLook

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(look == .original ? .none : .medium)
                    .scaledToFill()
                    .blur(radius: look == .crt ? 0.6 : 0)
                if look == .crt {
                    LookScanlines()
                }
            } else {
                Palette.tileLoading
            }
        }
        .frame(width: HubStyle.lookPreviewHeight * HubStyle.screenRatio, height: HubStyle.lookPreviewHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
        .accessibilityHidden(true)
    }
}

private struct LookScanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: Layout.scanlineThickness)),
                    with: .color(.black.opacity(0.35))
                )
                y += Layout.scanlinePitch
            }
        }
    }
}
