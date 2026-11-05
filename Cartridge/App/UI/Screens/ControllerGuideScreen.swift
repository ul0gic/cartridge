import SwiftUI

enum ControllerGuideTab {
    case menus
    case games
    case xbox
}

struct GuideCallout: Identifiable {
    enum Side {
        case left
        case right
        case top
    }

    let anchor: DualSenseControl
    let side: Side
    let button: String
    let action: String
    var detail: String?
    var also: [DualSenseControl] = []

    var id: String {
        button
    }

    var lit: Set<DualSenseControl> {
        Set([anchor] + also)
    }
}

enum ControllerGuide {
    static func callouts(_ tab: ControllerGuideTab) -> [GuideCallout] {
        switch tab {
        case .menus: menus
        case .games: games
        case .xbox: xbox
        }
    }

    static func initialFocus(_ tab: ControllerGuideTab) -> Int {
        tab == .xbox ? callouts(tab).firstIndex { $0.anchor == .l2 } ?? 0 : 0
    }

    static func footnote(_ tab: ControllerGuideTab) -> String {
        switch tab {
        case .menus:
            "Square, L2, R2, Create and the touchpad work in games only."
        case .games:
            "Rewind and fast forward work on NES, SNES and Genesis; on N64 and PS1, L2 and R2 are game buttons. "
                + "On NES, Cross jumps and Square or Circle runs. Xbox has its own page."
        case .xbox:
            "Xbox has no rewind or fast forward, so L2 and R2 are always the triggers."
        }
    }

    private static let menus = [
        GuideCallout(anchor: .l1, side: .left, button: "L1", action: "Switch page"),
        GuideCallout(anchor: .dpad, side: .left, button: "D-pad", action: "Move"),
        GuideCallout(anchor: .leftStick, side: .left, button: "Left stick", action: "Move"),
        GuideCallout(anchor: .r1, side: .right, button: "R1", action: "Switch page"),
        GuideCallout(anchor: .options, side: .right, button: "Options", action: "Settings"),
        GuideCallout(
            anchor: .triangle,
            side: .right,
            button: "Triangle",
            action: "Favorite a game",
            detail: "Remove from Continue playing · Group on Favorites"
        ),
        GuideCallout(anchor: .circle, side: .right, button: "Circle", action: "Back"),
        GuideCallout(anchor: .cross, side: .right, button: "Cross", action: "Select"),
        GuideCallout(anchor: .rightStick, side: .right, button: "Right stick", action: "Tilt the game box"),
    ]

    private static let xbox = [
        GuideCallout(anchor: .touchpad, side: .top, button: "Touchpad", action: "Click to pause and open the menu"),
        GuideCallout(
            anchor: .l2,
            side: .left,
            button: "L2",
            action: "Left trigger",
            detail: "Press partway to pull partway"
        ),
        GuideCallout(anchor: .l1, side: .left, button: "L1", action: "White button"),
        GuideCallout(
            anchor: .create,
            side: .left,
            button: "Create",
            action: "Hold to capture",
            detail: "Tap for Back"
        ),
        GuideCallout(anchor: .dpad, side: .left, button: "D-pad", action: "Direction pad"),
        GuideCallout(
            anchor: .leftStick,
            side: .left,
            button: "Left stick",
            action: "Left thumbstick",
            detail: "Click to press it"
        ),
        GuideCallout(
            anchor: .r2,
            side: .right,
            button: "R2",
            action: "Right trigger",
            detail: "Press partway to pull partway"
        ),
        GuideCallout(anchor: .r1, side: .right, button: "R1", action: "Black button"),
        GuideCallout(anchor: .options, side: .right, button: "Options", action: "Start"),
        GuideCallout(
            anchor: .circle,
            side: .right,
            button: "Face buttons",
            action: "Cross A, Circle B",
            detail: "Square X, Triangle Y",
            also: [.cross, .square, .triangle]
        ),
        GuideCallout(
            anchor: .rightStick,
            side: .right,
            button: "Right stick",
            action: "Right thumbstick",
            detail: "Click to press it"
        ),
    ]

    private static let games = [
        GuideCallout(anchor: .touchpad, side: .top, button: "Touchpad", action: "Click to pause and open the menu"),
        GuideCallout(anchor: .l2, side: .left, button: "L2", action: "Hold to rewind"),
        GuideCallout(anchor: .l1, side: .left, button: "L1", action: "Shoulder button"),
        GuideCallout(
            anchor: .create,
            side: .left,
            button: "Create",
            action: "Hold to capture",
            detail: "Tap for Select"
        ),
        GuideCallout(anchor: .dpad, side: .left, button: "D-pad", action: "Direction pad"),
        GuideCallout(
            anchor: .leftStick,
            side: .left,
            button: "Left stick",
            action: "Analog stick",
            detail: "Click for L3"
        ),
        GuideCallout(anchor: .r2, side: .right, button: "R2", action: "Hold to fast forward"),
        GuideCallout(anchor: .r1, side: .right, button: "R1", action: "Shoulder button"),
        GuideCallout(anchor: .options, side: .right, button: "Options", action: "Start"),
        GuideCallout(
            anchor: .circle,
            side: .right,
            button: "Face buttons",
            action: "Game buttons",
            also: [.cross, .square, .triangle]
        ),
        GuideCallout(
            anchor: .rightStick,
            side: .right,
            button: "Right stick",
            action: "Analog stick",
            detail: "N64 and PS1. Click for R3"
        ),
    ]
}

struct ControllerGuideScreen: View {
    let model: AppModel
    let tab: ControllerGuideTab

    var body: some View {
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: [
                Hint(kind: .sections, label: "Switch tab"),
                Hint(kind: .row, label: "Buttons"),
                Hint(kind: .back, label: "Back"),
            ],
            backdrop: { EmptyView() },
            content: {
                ControllerGuidePage(tab: tab, focus: model.focusedButton, glyphs: model.chrome.glyphs)
                    .padding(.horizontal, Layout.marginX)
                    .padding(.top, model.chrome.safeTop + Space.n2 + Layout.topbarHeight + Space.n6)
                    .padding(.bottom, Layout.hintbarHeight + Space.n4)
            }
        )
    }
}

struct ControllerGuidePage: View {
    let tab: ControllerGuideTab
    let focus: Int
    let glyphs: HintGlyphs?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.n5) {
            HStack(alignment: .center, spacing: Space.n6) {
                Text("Controller guide")
                    .typeStyle(.titleL)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.n6)
                GuideTabs(tab: tab, glyphs: glyphs)
            }
            GuideStage(tab: tab, focus: focus)
                .id(tab)
                .transition(.opacity)
        }
        .animation(Motion.easeInOut(Motion.sheet), value: tab)
    }
}

private struct GuideTabs: View {
    let tab: ControllerGuideTab
    let glyphs: HintGlyphs?

    var body: some View {
        HStack(spacing: Space.n3) {
            if let glyphs {
                GlyphLabel(symbol: glyphs.sectionLeft, size: Layout.glyphHint, color: Palette.textSecondary)
            }
            HStack(spacing: Space.half) {
                item("In menus", isActive: tab == .menus)
                item("In games", isActive: tab == .games)
                item("Xbox games", isActive: tab == .xbox)
            }
            .padding(Space.n1)
            .glassSurface(in: Capsule())
            if let glyphs {
                GlyphLabel(symbol: glyphs.sectionRight, size: Layout.glyphHint, color: Palette.textSecondary)
            }
        }
    }

    private func item(_ title: String, isActive: Bool) -> some View {
        Text(title)
            .typeStyle(.rail)
            .fontWeight(isActive ? .bold : .medium)
            .foregroundStyle(isActive ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, Space.n4)
            .frame(height: Layout.shellItemHeight)
            .background {
                if isActive {
                    Capsule().fill(Palette.textPrimary.opacity(0.14))
                }
            }
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

private struct GuideStage: View {
    let tab: ControllerGuideTab
    let focus: Int

    var body: some View {
        let callouts = ControllerGuide.callouts(tab)
        let lit = callouts.indices.contains(focus) ? callouts[focus] : nil
        GeometryReader { proxy in
            let plan = GuidePlan(size: proxy.size, callouts: callouts)
            ZStack(alignment: .topLeading) {
                RadialGradient(
                    colors: [Palette.controlFill, .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: plan.drawing.width * 0.62
                )
                .frame(width: plan.drawing.width * 1.3, height: plan.drawing.width * 1.3)
                .position(x: plan.drawing.midX, y: plan.drawing.midY)
                DualSenseDrawing(lit: lit?.lit ?? [])
                    .frame(width: plan.drawing.width, height: plan.drawing.height)
                    .position(x: plan.drawing.midX, y: plan.drawing.midY)
                GuideLeaders(plan: plan, litID: lit?.id)
                ForEach(plan.labels) { label in
                    GuideLabel(callout: label.callout, isLit: label.id == lit?.id)
                        .frame(width: label.frame.width, height: label.frame.height, alignment: label.alignment)
                        .position(x: label.frame.midX, y: label.frame.midY)
                }
                Text(ControllerGuide.footnote(tab))
                    .typeStyle(.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(width: plan.footnote.width, height: plan.footnote.height, alignment: .top)
                    .position(x: plan.footnote.midX, y: plan.footnote.midY)
            }
        }
    }
}

private struct GuidePlan {
    struct Label: Identifiable {
        let callout: GuideCallout
        let anchor: CGPoint
        let frame: CGRect

        var id: String {
            callout.id
        }

        var alignment: Alignment {
            switch callout.side {
            case .left: .topTrailing
            case .right: .topLeading
            case .top: .top
            }
        }

        var rowY: CGFloat {
            frame.minY + GuidePlan.rowHeight / 2
        }
    }

    static let column: CGFloat = 280
    static let gutter = Space.n8
    static let rowHeight = Layout.keycapHeight
    static let detailHeight = TypeStyle.meta.size * TypeStyle.meta.leading
    static let footnoteHeight = 2 * detailHeight

    let drawing: CGRect
    let footnote: CGRect
    let labels: [Label]

    init(size: CGSize, callouts: [GuideCallout]) {
        let board = DualSenseShape.board
        let above = Self.rowHeight + Space.n5
        let below = Space.n5 + Self.footnoteHeight
        let width = min(
            size.width - 2 * (Self.column + Self.gutter),
            (size.height - above - below) * board.width / board.height
        )
        let height = width * board.height / board.width
        let top = (size.height - above - height - below) / 2 + above
        drawing = CGRect(x: (size.width - width) / 2, y: top, width: width, height: height)
        footnote = CGRect(
            x: drawing.minX - Self.gutter,
            y: drawing.maxY + Space.n5,
            width: drawing.width + 2 * Self.gutter,
            height: Self.footnoteHeight
        )
        let drawing = drawing
        labels = [GuideCallout.Side.left, .right, .top].flatMap { side in
            Self.stack(callouts.filter { $0.side == side }, in: drawing)
        }
    }

    private static func anchor(_ callout: GuideCallout, in drawing: CGRect) -> CGPoint {
        let scale = drawing.width / DualSenseShape.board.width
        let center = DualSenseShape.center(callout.anchor)
        let reach = DualSenseShape.reach(callout.anchor)
        let point = switch callout.side {
        case .left: CGPoint(x: center.x - reach, y: center.y)
        case .right: CGPoint(x: center.x + reach, y: center.y)
        case .top: CGPoint(x: center.x, y: center.y - reach / 2)
        }
        return CGPoint(x: drawing.minX + point.x * scale, y: drawing.minY + point.y * scale)
    }

    private static func stack(_ callouts: [GuideCallout], in drawing: CGRect) -> [Label] {
        let anchored = callouts
            .map { (callout: $0, anchor: anchor($0, in: drawing)) }
            .sorted { $0.anchor.y < $1.anchor.y }
        var next = -CGFloat.infinity
        let frames = anchored.map { item in
            let height = rowHeight + (item.callout.detail == nil ? 0 : detailHeight)
            let top = max(item.anchor.y - rowHeight / 2, next)
            next = top + height + Space.n3
            return frame(item.callout.side, top: top, height: height, anchor: item.anchor, drawing: drawing)
        }
        let lift = max(0, (frames.last?.maxY ?? 0) - drawing.maxY)
        return zip(anchored, frames).map { item, frame in
            Label(callout: item.callout, anchor: item.anchor, frame: frame.offsetBy(dx: 0, dy: -lift))
        }
    }

    private static func frame(
        _ side: GuideCallout.Side,
        top: CGFloat,
        height: CGFloat,
        anchor: CGPoint,
        drawing: CGRect
    ) -> CGRect {
        switch side {
        case .left:
            CGRect(x: drawing.minX - gutter - column, y: top, width: column, height: height)
        case .right:
            CGRect(x: drawing.maxX + gutter, y: top, width: column, height: height)
        case .top:
            CGRect(x: anchor.x - column, y: drawing.minY - Space.n5 - rowHeight, width: 2 * column, height: height)
        }
    }
}

private struct GuideLeaders: View {
    let plan: GuidePlan
    let litID: String?

    var body: some View {
        Canvas { context, _ in
            for label in plan.labels {
                let isLit = label.id == litID
                let line = path(label)
                context.stroke(line, with: .color(Palette.focusGap.opacity(0.7)), lineWidth: 4)
                context.stroke(
                    line,
                    with: .color(isLit ? Palette.focusRing : Palette.textTertiary),
                    lineWidth: isLit ? 2 : 1.25
                )
                let dot = Path(ellipseIn: CGRect(x: label.anchor.x - 4, y: label.anchor.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(isLit ? Palette.focusRing : Palette.textSecondary))
                context.stroke(dot, with: .color(Palette.focusGap), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func path(_ label: GuidePlan.Label) -> Path {
        let anchor = label.anchor
        let drawing = plan.drawing
        return Path { path in
            path.move(to: anchor)
            switch label.callout.side {
            case .left:
                path.addLine(to: CGPoint(x: min(anchor.x, drawing.minX - Space.n2), y: anchor.y))
                path.addLine(to: CGPoint(x: label.frame.maxX + Space.n5, y: label.rowY))
                path.addLine(to: CGPoint(x: label.frame.maxX + Space.n3, y: label.rowY))
            case .right:
                path.addLine(to: CGPoint(x: max(anchor.x, drawing.maxX + Space.n2), y: anchor.y))
                path.addLine(to: CGPoint(x: label.frame.minX - Space.n5, y: label.rowY))
                path.addLine(to: CGPoint(x: label.frame.minX - Space.n3, y: label.rowY))
            case .top:
                path.addLine(to: CGPoint(x: anchor.x, y: label.frame.minY + GuidePlan.rowHeight + Space.n2))
            }
        }
    }
}

private struct GuideLabel: View {
    let callout: GuideCallout
    let isLit: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.n3) {
            if callout.side == .left {
                words(alignment: .trailing)
                GuideKey(label: callout.button, isLit: isLit)
            } else {
                GuideKey(label: callout.button, isLit: isLit)
                words(alignment: .leading)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([callout.button, callout.action, callout.detail].compactMap(\.self).joined(separator: ", "))
    }

    private func words(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(callout.action)
                .typeStyle(.body)
                .fontWeight(.semibold)
                .foregroundStyle(isLit ? Palette.textPrimary : Palette.textSecondary)
            if let detail = callout.detail {
                Text(detail)
                    .typeStyle(.meta)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct GuideKey: View {
    let label: String
    let isLit: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.keycap)
        Text(label)
            .typeStyle(.keycap)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isLit ? Palette.actionText : Palette.textPrimary)
            .padding(.horizontal, Space.n2)
            .frame(minWidth: Layout.keycapMinWidth, minHeight: Layout.keycapHeight)
            .background(isLit ? Palette.actionFill : .clear, in: shape)
            .overlay {
                shape.strokeBorder(isLit ? .clear : Palette.keycapStroke, lineWidth: Layout.strokeKeycap)
            }
    }
}
