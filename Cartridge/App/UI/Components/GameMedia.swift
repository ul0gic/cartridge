import SwiftUI

extension GameSystem {
    var isDisc: Bool {
        self == .ps1 || self == .xbox
    }

    var insertSchedule: InsertSchedule {
        ConsoleInsertFrame(system: self, time: 0) == nil ? .slot : .console
    }

    func mediaRect(in caseSize: CGSize) -> CGRect {
        let width = caseSize.width
        let height = caseSize.height
        let share: CGFloat
        let aspect: CGFloat
        switch self {
        case .nes: (share, aspect) = (0.84, 133.0 / 120)
        case .snes: (share, aspect) = (0.72, 88.0 / 136)
        case .n64: (share, aspect) = (0.6, 76.0 / 116)
        case .genesis: (share, aspect) = (0.7, 70.3 / 108)
        case .ps1:
            let art = 0.96 * height
            let side = art * 0.92
            return CGRect(
                x: width - 0.02 * height - art / 2 - side / 2,
                y: (height - side) / 2,
                width: side,
                height: side
            )
        case .xbox:
            let side = 0.89 * width
            return CGRect(x: 0.055 * width, y: (height - side) / 2, width: side, height: side)
        }
        let mediaWidth = width * share
        let mediaHeight = mediaWidth * aspect
        return CGRect(
            x: (width - mediaWidth) / 2,
            y: height - 0.04 * height - mediaHeight,
            width: mediaWidth,
            height: mediaHeight
        )
    }

    var slotPlastic: Color {
        switch self {
        case .nes: MediaInk.gray(0x8E, 0x8E, 0x8B)
        case .snes: MediaInk.gray(0xBA, 0xB8, 0xB2)
        case .genesis: MediaInk.gray(0x1C, 0x1C, 0x1F)
        case .n64: MediaInk.gray(0x5F, 0x60, 0x66)
        case .ps1: MediaInk.gray(0xB9, 0xBB, 0xBF)
        case .xbox: MediaInk.gray(0x1D, 0x1F, 0x1D)
        }
    }

    var powerLED: Color {
        isDisc ? MediaInk.gray(0x2E, 0xBD, 0x59) : MediaInk.gray(0xE1, 0x26, 0x2F)
    }
}

enum MediaInk {
    static func gray(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

struct GameMedia: View {
    let title: String
    let system: GameSystem
    let art: TileArt

    var body: some View {
        Canvas { context, size in
            let board = Self.board(for: system)
            context.scaleBy(x: size.width / board.width, y: size.height / board.height)
            let sketch = MediaSketch(context: context, label: label(in: context))
            switch system {
            case .nes: sketch.nes()
            case .snes: sketch.snes()
            case .n64: sketch.n64()
            case .genesis: sketch.genesis()
            case .ps1, .xbox: sketch.disc()
            }
        }
    }

    private func label(in context: GraphicsContext) -> MediaLabel {
        guard case .image(let loaded) = art else {
            return .title(context.resolve(Text(title).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)))
        }
        return .art(MediaArt(
            image: context.resolve(Image(decorative: loaded.image, scale: 1)),
            size: CGSize(width: loaded.image.width, height: loaded.image.height)
        ))
    }

    static func board(for system: GameSystem) -> CGSize {
        switch system {
        case .nes: CGSize(width: 120, height: 133)
        case .snes: CGSize(width: 136, height: 88)
        case .n64: CGSize(width: 116, height: 76)
        case .genesis: CGSize(width: 108, height: 70.3)
        case .ps1, .xbox: CGSize(width: 120, height: 120)
        }
    }
}

private enum MediaLabel {
    case art(MediaArt)
    case title(GraphicsContext.ResolvedText)
}

private struct MediaArt {
    let image: GraphicsContext.ResolvedImage
    let size: CGSize
}

private struct MediaSketch {
    let context: GraphicsContext
    let label: MediaLabel

    private static let gloss = Gradient(stops: [
        .init(color: .white.opacity(0.22), location: 0),
        .init(color: .white.opacity(0), location: 0.45),
        .init(color: .black.opacity(0.12), location: 1),
    ])

    func nes() {
        let body = Self.nesShell
        let recess = MediaInk.gray(0x74, 0x74, 0x71)
        let ridge = MediaInk.gray(0x8E, 0x8E, 0x8B)
        fill(body, top: MediaInk.gray(0xA2, 0xA2, 0x9F), bottom: MediaInk.gray(0x7D, 0x7D, 0x7A))
        context.fill(Path(CGRect(x: 18.2, y: 1, width: 25.6, height: 131)), with: .color(recess))
        context.stroke(
            Path(CGRect(x: 17.9, y: 1, width: 26.2, height: 15.7)),
            with: .color(MediaInk.gray(0x5E, 0x5E, 0x5B)),
            lineWidth: 0.6
        )
        ridges(CGRect(x: 19.7, y: 2.4, width: 22.6, height: 1.8), count: 3, step: 4.4, color: ridge)
        ridges(CGRect(x: 19.7, y: 19.7, width: 22.6, height: 1.8), count: 20, step: 5.12, color: ridge)
        let foot = MediaInk.gray(0x80, 0x80, 0x7D)
        context.fill(Path(CGRect(x: 18.2, y: 119, width: 25.6, height: 13)), with: .color(foot))
        drawLabel(CGRect(x: 47.4, y: 5.8, width: 55.8, height: 91.5), radius: 1)
        context.stroke(body, with: .color(.white.opacity(0.3)), lineWidth: 1)
    }

    private static let nesShell: Path = {
        var shell = Path()
        shell.addLines([
            CGPoint(x: 0, y: 0), CGPoint(x: 4.2, y: 0), CGPoint(x: 4.2, y: 1.8), CGPoint(x: 11.3, y: 1.8),
            CGPoint(x: 11.3, y: 0), CGPoint(x: 107.7, y: 0), CGPoint(x: 107.7, y: 1.8), CGPoint(x: 114.1, y: 1.8),
            CGPoint(x: 114.1, y: 0), CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 108), CGPoint(x: 113.1, y: 108),
            CGPoint(x: 113.1, y: 133), CGPoint(x: 6.9, y: 133), CGPoint(x: 6.9, y: 108), CGPoint(x: 0, y: 108),
        ])
        shell.closeSubpath()
        return shell
    }()

    func snes() {
        fill(Self.snesShell, top: MediaInk.gray(0xC9, 0xC7, 0xC1), bottom: MediaInk.gray(0xA4, 0xA2, 0x9C))
        var grips = context
        grips.clip(to: Self.snesShell)
        grips.fill(Path(CGRect(x: 0, y: 0, width: 22, height: 88)), with: .color(.black.opacity(0.07)))
        grips.fill(Path(CGRect(x: 114, y: 0, width: 22, height: 88)), with: .color(.black.opacity(0.07)))
        let edge = MediaInk.gray(0x8F, 0x8D, 0x87)
        for x in [0.0, 114] {
            for y in [16.3, 30.7, 45, 59.3, 73.7] {
                context.fill(Path(CGRect(x: x, y: y, width: 22, height: 0.8)), with: .color(edge))
                let light = Path(CGRect(x: x, y: y + 0.8, width: 22, height: 0.5))
                context.fill(light, with: .color(.white.opacity(0.35)))
            }
        }
        context.fill(Path(CGRect(x: 21.6, y: 0, width: 0.7, height: 88)), with: .color(edge))
        context.fill(Path(CGRect(x: 113.7, y: 0, width: 0.7, height: 88)), with: .color(.white.opacity(0.45)))
        for x in [11.0, 125] {
            context.fill(circle(CGPoint(x: x, y: 80.8), 1.6), with: .color(.white.opacity(0.4)))
            context.fill(circle(CGPoint(x: x, y: 80.8), 1.3), with: .color(MediaInk.gray(0x5F, 0x5D, 0x58)))
            context.fill(circle(CGPoint(x: x, y: 80.6), 0.55), with: .color(MediaInk.gray(0x2C, 0x2B, 0x28)))
        }
        context.fill(
            Path(
                roundedRect: CGRect(x: 26.5, y: 0, width: 83, height: 37),
                cornerRadii: RectangleCornerRadii(bottomLeading: 3.5, bottomTrailing: 3.5)
            ),
            with: .color(MediaInk.gray(0x9A, 0x98, 0x92))
        )
        drawLabel(CGRect(x: 27.3, y: 0, width: 81.4, height: 36.2), radius: 2.6)
        let panelEdge = MediaInk.gray(0x86, 0x84, 0x7E)
        fill(Self.snesPanel(inset: 0), top: MediaInk.gray(0x9E, 0x9C, 0x96), bottom: MediaInk.gray(0xB3, 0xB1, 0xAB))
        context.stroke(Self.snesPanel(inset: 0), with: .color(panelEdge), lineWidth: 0.8)
        context.stroke(Self.snesPanel(inset: -0.8), with: .color(.white.opacity(0.5)), lineWidth: 0.5)
        var rib = Path()
        rib.addLines([CGPoint(x: 57, y: 50.4), CGPoint(x: 80, y: 50.4), CGPoint(x: 80, y: 71.5)])
        rib.addLine(to: CGPoint(x: 60, y: 76.5))
        rib.addQuadCurve(to: CGPoint(x: 57, y: 74), control: CGPoint(x: 57, y: 77))
        rib.closeSubpath()
        context.fill(rib, with: .color(.white.opacity(0.14)))
        context.stroke(line(57, 50.4, 57, 74), with: .color(panelEdge), lineWidth: 0.6)
        context.stroke(line(80, 50.4, 80, 71.5), with: .color(.white.opacity(0.5)), lineWidth: 0.6)
        context.stroke(line(22, 0.5, 114, 0.5), with: .color(.white.opacity(0.55)), lineWidth: 1)
    }

    private static let snesShell: Path = {
        var shell = Path()
        shell.addLines([CGPoint(x: 22, y: 0), CGPoint(x: 114, y: 0), CGPoint(x: 114, y: 2), CGPoint(x: 133, y: 2)])
        shell.addQuadCurve(to: CGPoint(x: 136, y: 5), control: CGPoint(x: 136, y: 2))
        shell.addLine(to: CGPoint(x: 136, y: 85.5))
        shell.addQuadCurve(to: CGPoint(x: 133.5, y: 88), control: CGPoint(x: 136, y: 88))
        shell.addLine(to: CGPoint(x: 2.5, y: 88))
        shell.addQuadCurve(to: CGPoint(x: 0, y: 85.5), control: CGPoint(x: 0, y: 88))
        shell.addLine(to: CGPoint(x: 0, y: 5))
        shell.addQuadCurve(to: CGPoint(x: 3, y: 2), control: CGPoint(x: 0, y: 2))
        shell.addLine(to: CGPoint(x: 22, y: 2))
        shell.closeSubpath()
        return shell
    }()

    private static func snesPanel(inset: CGFloat) -> Path {
        let left = 31 + inset
        let right = 105 - inset
        let top = 50 + inset
        var panel = Path()
        panel.move(to: CGPoint(x: left, y: 88))
        panel.addLine(to: CGPoint(x: left, y: 54))
        panel.addQuadCurve(to: CGPoint(x: 35, y: top), control: CGPoint(x: left, y: top))
        panel.addLine(to: CGPoint(x: 101, y: top))
        panel.addQuadCurve(to: CGPoint(x: right, y: 54), control: CGPoint(x: right, y: top))
        panel.addLine(to: CGPoint(x: right, y: 88))
        return panel
    }

    func n64() {
        let groove = MediaInk.gray(0x3A, 0x3B, 0x40)
        fill(Self.n64Shell, top: MediaInk.gray(0x6E, 0x6F, 0x75), bottom: MediaInk.gray(0x4A, 0x4B, 0x50))
        for x in [22.5, 93.5] {
            context.stroke(
                Path { $0.addLines([CGPoint(x: x, y: 4.3), CGPoint(x: x, y: 76)]) },
                with: .color(groove),
                lineWidth: 0.9
            )
        }
        for flip in [false, true] {
            let x = { (value: CGFloat) in flip ? 116 - value : value }
            var tab = Path()
            tab.move(to: CGPoint(x: x(0.7), y: 54.4))
            tab.addLine(to: CGPoint(x: x(3.4), y: 54.4))
            tab.addQuadCurve(to: CGPoint(x: x(6.9), y: 57.8), control: CGPoint(x: x(6.9), y: 54.4))
            tab.addLine(to: CGPoint(x: x(6.9), y: 76))
            context.stroke(tab, with: .color(groove.opacity(0.7)), lineWidth: 0.5)
        }
        var label = Path()
        label.move(to: CGPoint(x: 28.8, y: 10.5))
        label.addQuadCurve(to: CGPoint(x: 32.6, y: 7.4), control: CGPoint(x: 28.8, y: 7.6))
        label.addQuadCurve(to: CGPoint(x: 83.4, y: 7.4), control: CGPoint(x: 58, y: 4))
        label.addQuadCurve(to: CGPoint(x: 87.2, y: 10.5), control: CGPoint(x: 87.2, y: 7.6))
        label.addLine(to: CGPoint(x: 87.2, y: 67))
        label.addQuadCurve(to: CGPoint(x: 83.6, y: 70.6), control: CGPoint(x: 87.2, y: 70.6))
        label.addLine(to: CGPoint(x: 32.4, y: 70.6))
        label.addQuadCurve(to: CGPoint(x: 28.8, y: 67), control: CGPoint(x: 28.8, y: 70.6))
        label.closeSubpath()
        drawLabel(label)
        context.stroke(Self.n64Shell, with: .color(.white.opacity(0.3)), lineWidth: 1)
    }

    private static let n64Shell: Path = {
        var shell = Path()
        shell.move(to: CGPoint(x: 0, y: 12.6))
        shell.addQuadCurve(to: CGPoint(x: 22.5, y: 4.3), control: CGPoint(x: 6, y: 7.5))
        shell.addQuadCurve(to: CGPoint(x: 93.5, y: 4.3), control: CGPoint(x: 58, y: -3.9))
        shell.addQuadCurve(to: CGPoint(x: 116, y: 12.6), control: CGPoint(x: 110, y: 7.5))
        shell.addLine(to: CGPoint(x: 116, y: 73))
        shell.addQuadCurve(to: CGPoint(x: 113, y: 76), control: CGPoint(x: 116, y: 76))
        shell.addLine(to: CGPoint(x: 3, y: 76))
        shell.addQuadCurve(to: CGPoint(x: 0, y: 73), control: CGPoint(x: 0, y: 76))
        shell.closeSubpath()
        return shell
    }()

    func genesis() {
        var shell = Path()
        shell.move(to: CGPoint(x: 0, y: 70.3))
        shell.addLine(to: CGPoint(x: 0, y: 2.7))
        shell.addQuadCurve(to: CGPoint(x: 2.7, y: 0), control: CGPoint(x: 0, y: 0))
        shell.addLine(to: CGPoint(x: 14.5, y: 0))
        shell.addQuadCurve(to: CGPoint(x: 16, y: 1.5), control: CGPoint(x: 16, y: 0))
        shell.addLine(to: CGPoint(x: 16, y: 2.7))
        shell.addLine(to: CGPoint(x: 92, y: 2.7))
        shell.addLine(to: CGPoint(x: 92, y: 1.5))
        shell.addQuadCurve(to: CGPoint(x: 93.5, y: 0), control: CGPoint(x: 92, y: 0))
        shell.addLine(to: CGPoint(x: 105.3, y: 0))
        shell.addQuadCurve(to: CGPoint(x: 108, y: 2.7), control: CGPoint(x: 108, y: 0))
        shell.addLine(to: CGPoint(x: 108, y: 70.3))
        shell.closeSubpath()
        fill(shell, top: MediaInk.gray(0x26, 0x26, 0x2A), bottom: MediaInk.gray(0x12, 0x12, 0x14))
        let recess = CGRect(x: 16, y: 2.7, width: 76, height: 59.3)
        context.fill(
            Path(roundedRect: recess, cornerRadii: RectangleCornerRadii(bottomLeading: 2, bottomTrailing: 2)),
            with: .color(MediaInk.gray(0x0C, 0x0C, 0x0E))
        )
        drawLabel(recess.insetBy(dx: 1.2, dy: 1.2), radius: 1.2)
        context.stroke(shell, with: .color(.white.opacity(0.25)), lineWidth: 1)
    }

    func disc() {
        let center = CGPoint(x: 60, y: 60)
        var disc = context
        var face = circle(center, 60)
        face.addPath(circle(center, 7.5))
        disc.clip(to: face, style: FillStyle(eoFill: true))
        disc.fill(circle(center, 60), with: .color(MediaInk.gray(0x11, 0x11, 0x14)))
        var art = disc
        art.clip(to: circle(center, 58))
        Self.drawArt(label, in: CGRect(x: 2, y: 2, width: 116, height: 116), context: art)
        disc.fill(
            circle(center, 60),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0.2),
                    .init(color: .white.opacity(0.28), location: 0.42),
                    .init(color: .white.opacity(0), location: 0.5),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 120, y: 120)
            )
        )
        disc.fill(circle(center, 17), with: .color(MediaInk.gray(210, 218, 232).opacity(0.72)))
        disc.fill(circle(center, 12), with: .color(MediaInk.gray(150, 158, 172).opacity(0.8)))
        disc.stroke(circle(center, 17), with: .color(.white.opacity(0.6)), lineWidth: 0.6)
        disc.stroke(circle(center, 59.4), with: .color(.white.opacity(0.4)), lineWidth: 1)
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }

    private func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        Path { $0.addLines([CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1)]) }
    }

    private func fill(_ path: Path, top: Color, bottom: Color) {
        let bounds = path.boundingRect
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
            )
        )
    }

    private func ridges(_ first: CGRect, count: Int, step: CGFloat, color: Color) {
        for index in 0..<count {
            let ridge = first.offsetBy(dx: 0, dy: CGFloat(index) * step)
            context.fill(Path(roundedRect: ridge, cornerRadius: ridge.height / 2), with: .color(color))
        }
    }

    private func drawLabel(_ rect: CGRect, radius: CGFloat) {
        drawLabel(Path(roundedRect: rect, cornerRadius: radius))
    }

    private func drawLabel(_ shape: Path) {
        let rect = shape.boundingRect
        var inside = context
        inside.clip(to: shape)
        Self.drawArt(label, in: rect, context: inside)
        context.fill(
            shape,
            with: .linearGradient(Self.gloss, startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY))
        )
        context.stroke(shape, with: .color(.black.opacity(0.4)), lineWidth: 0.6)
    }

    private static func drawArt(_ label: MediaLabel, in rect: CGRect, context: GraphicsContext) {
        switch label {
        case .art(let art):
            let fill = max(rect.width / art.size.width, rect.height / art.size.height)
            let drawn = CGSize(width: art.size.width * fill, height: art.size.height * fill)
            context.draw(
                art.image,
                in: CGRect(
                    x: rect.midX - drawn.width / 2,
                    y: rect.midY - drawn.height / 2,
                    width: drawn.width,
                    height: drawn.height
                )
            )
        case .title(let text):
            context.fill(Path(rect), with: .color(MediaInk.gray(0x22, 0x23, 0x28)))
            context.draw(text, in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.12))
        }
    }
}

struct InsertFrame {
    let time: Double
    let press: Double
    let chrome: Double
    let square: Double
    let glide: Double
    let dim: Double
    let flap: Double
    let rise: Double
    let lid: Double
    let lift: Double
    let spin: Double
    let recede: Double
    let floor: Double
    let slot: Double
    let hang: Double
    let lay: Double
    let drop: Double
    let settle: Double
    let seat: Double
    let led: Double
    let flash: Double
    let shake: Double
    let jolt: Double
    let black: Double
    let console: ConsoleInsertFrame?

    init(milliseconds: Double, system: GameSystem) {
        let schedule = system.insertSchedule
        let time = milliseconds / schedule.pace
        self.time = time
        console = ConsoleInsertFrame(system: system, time: time)
        press = Self.track(time, Self.pressKeys)
        chrome = InsertBeat.chrome.progress(time)
        square = Motion.insertSquare.value(target: 1.0, time: time / 1000)
        glide = InsertBeat.glide.progress(time)
        dim = InsertBeat.dim.progress(time)
        flap = schedule.flap.progress(time)
        rise = schedule.rise.progress(time)
        lid = XboxDisc.boxBeats(in: console).lid.progress(time)
        lift = XboxDisc.boxBeats(in: console).lift.progress(time)
        spin = InsertBeat.spin.progress(time)
        recede = (system.isDisc && console == nil ? InsertBeat.discRecede : schedule.recede).progress(time)
        floor = schedule.recede.progress(time)
        slot = InsertBeat.slot.progress(time)
        hang = InsertBeat.hang.progress(time)
        lay = InsertBeat.lay.progress(time)
        drop = InsertBeat.drop.progress(time)
        settle = InsertBeat.settle.progress(time)
        seat = InsertBeat.seat.progress(time)
        led = InsertBeat.led.progress(time)
        flash = schedule.flashUp.progress(time) - schedule.flashDown.progress(time)
        shake = console == nil ? Self.track(time, Self.shakeKeys) : 0
        jolt = Self.track(time, Self.joltKeys)
        black = schedule.black.progress(time)
    }

    private static let pressKeys = [
        InsertKey(0, 1, Motion.insertOut),
        InsertKey(40, 0.96, Motion.insertOut),
        InsertKey(100, 1, .linear),
    ]
    private static let shakeKeys = [
        InsertKey(1000, 0, Motion.insertOut),
        InsertKey(1030, 3, Motion.insertOut),
        InsertKey(1070, -1.5, Motion.insertOut),
        InsertKey(1110, 0, .linear),
    ]
    private static let joltKeys = [
        InsertKey(1000, 0, Motion.insertOut),
        InsertKey(1040, 1, Motion.insertOut),
        InsertKey(1100, 0, .linear),
    ]

    func mediaInFront(depth: CGFloat, scale: CGFloat) -> Bool {
        640 * Double(scale) * recede >= Double(depth) / 2
    }

    var discInTray: Bool {
        time < XboxDisc.boxBeats(in: console).lift.start
    }

    func casePose(system: GameSystem, scale: CGFloat) -> CaseInsertPose {
        let receding = Double(scale) * recede
        return CaseInsertPose(
            square: square,
            flap: system.isDisc ? 1 : 1 - flap,
            lid: system.isDisc ? -(system == .xbox ? XboxDisc.lidOpen : 105) * lid : 0,
            lidShade: 0.7 * lid,
            fade: 1 - recede,
            shift: SIMD3(0, 40 * receding, -640 * receding),
            floor: 1 - floor,
            discInTray: system.isDisc && discInTray
        )
    }

    static func track(_ time: Double, _ keys: [InsertKey]) -> Double {
        for (from, to) in zip(keys, keys.dropFirst()) where time < to.time {
            guard time > from.time else { return from.value }
            return from.value + (to.value - from.value) * from.curve
                .value(at: (time - from.time) / (to.time - from.time))
        }
        return keys[keys.count - 1].value
    }
}
