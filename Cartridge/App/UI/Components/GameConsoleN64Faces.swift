import SwiftUI

enum N64Ink {
    static let shellLit = MediaInk.gray(0x58, 0x59, 0x5F)
    static let shell = MediaInk.gray(0x40, 0x41, 0x47)
    static let shellShade = MediaInk.gray(0x2B, 0x2C, 0x31)
    static let base = MediaInk.gray(0x1E, 0x1F, 0x23)
    static let vent = MediaInk.gray(0x0D, 0x0D, 0x0F)
    static let knob = MediaInk.gray(0x50, 0x51, 0x57)
    static let port = MediaInk.gray(0xC4, 0xC5, 0xC8)
    static let portShade = MediaInk.gray(0x8E, 0x8F, 0x93)
    static let badgeLit = MediaInk.gray(0x2A, 0x2B, 0x31)
    static let badge = MediaInk.gray(0x11, 0x11, 0x14)
    static let lettering = MediaInk.gray(0x8F, 0x90, 0x97)
    static let flap = MediaInk.gray(0xAE, 0xAF, 0xB2)
    static let ledOff = MediaInk.gray(0x3A, 0x17, 0x17)
    static let cart = MediaInk.gray(0x6E, 0x6F, 0x75)
    static let cartShade = MediaInk.gray(0x4A, 0x4B, 0x50)
}

struct N64Top: View {
    let power: Double
    let led: Double

    var body: some View {
        Canvas { context, size in
            let unit = size.width / N64Shape.width
            let glow = context
            context.scaleBy(x: unit, y: size.height / N64Shape.depth)
            let sketch = ConsoleSketch(context: context, ink: N64Ink.lettering)
            deck(sketch)
            hump(sketch)
            vent(sketch)
            lid(sketch)
            for (index, x) in N64Shape.switches.enumerated() {
                slider(sketch, x: x, travel: index == 0 ? power : 0)
            }
            sketch.word("POWER", size: 3.2, tracking: 0.3, at: CGPoint(x: 44, y: 178))
            sketch.word("RESET", size: 3.2, tracking: 0.3, at: CGPoint(x: 216, y: 178))
            ConsoleLED(
                rect: N64Shape.led,
                off: N64Ink.ledOff,
                shine: .white.opacity(0.7),
                color: GameSystem.n64.powerLED
            )
            .draw(led, in: context, glow: glow, unit: unit)
            var edge = Path()
            edge.move(to: CGPoint(x: 0, y: N64Shape.depth - N64Shape.corner))
            edge.addLine(to: CGPoint(x: N64Shape.corner, y: N64Shape.depth))
            edge.addLine(to: CGPoint(x: N64Shape.width - N64Shape.corner, y: N64Shape.depth))
            edge.addLine(to: CGPoint(x: N64Shape.width, y: N64Shape.depth - N64Shape.corner))
            context.stroke(edge, with: .color(.white.opacity(0.22)), lineWidth: 0.8)
        }
    }

    private func deck(_ sketch: ConsoleSketch) {
        let width = N64Shape.width
        let depth = N64Shape.depth
        let corner = N64Shape.corner
        let slot = TopLoader.n64.slot
        var shell = Path()
        shell.move(to: CGPoint(x: corner, y: 0))
        shell.addLine(to: CGPoint(x: width - corner, y: 0))
        shell.addQuadCurve(to: CGPoint(x: width, y: corner), control: CGPoint(x: width, y: 0))
        shell.addLine(to: CGPoint(x: width, y: depth - corner))
        shell.addLine(to: CGPoint(x: width - corner, y: depth))
        shell.addLine(to: CGPoint(x: corner, y: depth))
        shell.addLine(to: CGPoint(x: 0, y: depth - corner))
        shell.addLine(to: CGPoint(x: 0, y: corner))
        shell.addQuadCurve(to: CGPoint(x: corner, y: 0), control: CGPoint.zero)
        shell.closeSubpath()
        shell.addPath(
            Path(
                roundedRect: CGRect(
                    x: slot.left,
                    y: slot.back + depth,
                    width: slot.right - slot.left,
                    height: slot.front - slot.back
                ),
                cornerRadius: 1.5
            )
        )
        sketch.fill(shell, top: N64Ink.shell, bottom: N64Ink.shellLit, eoFill: true)
        let emblem = Path(roundedRect: CGRect(x: 108, y: 22, width: 44, height: 10), cornerRadius: 5)
        sketch.context.fill(emblem, with: .color(.black.opacity(0.12)))
        sketch.context.stroke(emblem, with: .color(.black.opacity(0.45)), lineWidth: 0.5)
        sketch.rect(112, 31.6, 36, 0.5, .white.opacity(0.1))
    }

    private func hump(_ sketch: ConsoleSketch) {
        let hump = N64Shape.hump
        let footprint = CGRect(x: hump.minX - 2, y: hump.minY + N64Shape.depth - 2, width: hump.width + 4, height: 68)
        sketch.context.fill(Path(roundedRect: footprint, cornerRadius: 13), with: .color(.black.opacity(0.35)))
    }

    private func vent(_ sketch: ConsoleSketch) {
        var recess = Path()
        recess.move(to: CGPoint(x: 86, y: 103))
        recess.addQuadCurve(to: CGPoint(x: 174, y: 103), control: CGPoint(x: 130, y: 114))
        recess.addLine(to: CGPoint(x: 174, y: 126))
        recess.addQuadCurve(to: CGPoint(x: 86, y: 126), control: CGPoint(x: 130, y: 136))
        recess.closeSubpath()
        sketch.context.fill(recess, with: .color(.black.opacity(0.25)))
        for slat in 0..<20 {
            let x = 89 + Double(slat) * 4.2
            let bow = 5 * (1 - pow((x + 1 - 130) / 44, 2))
            sketch.context.fill(
                Path(roundedRect: CGRect(x: x, y: 105 + bow, width: 2.1, height: 14), cornerRadius: 1),
                with: .color(N64Ink.vent)
            )
        }
    }

    private func lid(_ sketch: ConsoleSketch) {
        let context = sketch.context
        let cover = Path(roundedRect: CGRect(x: 104, y: 134, width: 52, height: 40), cornerRadius: 5)
        context.fill(cover, with: .color(.black.opacity(0.1)))
        context.stroke(cover, with: .color(.black.opacity(0.55)), lineWidth: 0.6)
        sketch.rect(105, 173.4, 50, 0.5, .white.opacity(0.12))
        let tab = Path(roundedRect: CGRect(x: 124, y: 130, width: 12, height: 6), cornerRadius: 2)
        sketch.fill(tab, top: N64Ink.knob, bottom: N64Ink.shellShade)
        context.stroke(tab, with: .color(.black.opacity(0.5)), lineWidth: 0.4)
        for x in [121.0, 127, 133, 139] {
            context.fill(
                Path(ellipseIn: CGRect(x: x - 0.7, y: 141.3, width: 1.4, height: 1.4)),
                with: .color(.black.opacity(0.6))
            )
        }
    }

    private func slider(_ sketch: ConsoleSketch, x: Double, travel: Double) {
        let context = sketch.context
        let recess = Path(roundedRect: CGRect(x: x, y: 126, width: 28, height: 44), cornerRadius: 14)
        context.fill(recess, with: .color(.black.opacity(0.4)))
        context.stroke(recess, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
        let key = Path(roundedRect: CGRect(x: x + 6, y: 132 + travel, width: 16, height: 16), cornerRadius: 3)
        sketch.fill(key, top: N64Ink.knob, bottom: N64Ink.shellShade)
        context.stroke(key, with: .color(.black.opacity(0.6)), lineWidth: 0.4)
        for y in [136.0, 139, 142, 145] {
            sketch.rect(x + 8, y + travel, 12, 0.6, .black.opacity(0.4))
        }
        sketch.rect(x + 7, 132.5 + travel, 14, 0.6, .white.opacity(0.25))
    }
}

struct N64HumpTop: View {
    var body: some View {
        Canvas { context, size in
            let hump = N64Shape.hump
            context.scaleBy(x: size.width / hump.width, y: size.height / hump.height)
            let sketch = ConsoleSketch(context: context, ink: N64Ink.lettering)
            let slot = TopLoader.n64.slot
            let hole = Path(
                roundedRect: CGRect(
                    x: slot.left - hump.minX,
                    y: slot.back - hump.minY,
                    width: slot.right - slot.left,
                    height: slot.front - slot.back
                ),
                cornerRadius: 1.5
            )
            var raised = Path(roundedRect: CGRect(origin: .zero, size: hump.size), cornerRadius: 12)
            raised.addPath(hole)
            sketch.fill(raised, top: N64Ink.shell, bottom: N64Ink.shellLit, eoFill: true)
            context.stroke(hole, with: .color(.black.opacity(0.75)), lineWidth: 0.9)
            let opening = hole.boundingRect
            sketch.rect(opening.minX, opening.maxY + 0.5, opening.width, 0.6, .white.opacity(0.25))
            sketch.rect(12, hump.height - 1.1, hump.width - 24, 0.8, .white.opacity(0.3))
        }
    }
}

struct N64Front: View {
    var body: some View {
        Canvas { context, size in
            let width = N64Shape.frontWidth
            let height = N64Shape.height
            context.scaleBy(x: size.width / width, y: size.height / height)
            let sketch = ConsoleSketch(context: context, ink: N64Ink.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                top: N64Ink.shellLit,
                bottom: N64Ink.shellShade
            )
            sketch.rect(0, 0, width, 4, .white.opacity(0.06))
            sketch.rect(0, 0, width, 0.7, .white.opacity(0.25))
            for x in N64Shape.ports {
                port(sketch, x: x)
            }
            let badge = Path(roundedRect: CGRect(x: width / 2 - 24, y: 30, width: 48, height: 28), cornerRadius: 5)
            sketch.fill(badge, top: N64Ink.badgeLit, bottom: N64Ink.badge)
            context.stroke(badge, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            context.fill(
                Path(roundedRect: CGRect(x: width / 2 - 22, y: 31.5, width: 44, height: 10), cornerRadius: 4),
                with: .color(.white.opacity(0.07))
            )
            sketch.rect(0, 64, width, height - 64, N64Ink.base)
            sketch.rect(0, 64, width, 0.6, .white.opacity(0.08))
        }
    }

    private func port(_ sketch: ConsoleSketch, x: Double) {
        let context = sketch.context
        let socket = Path(roundedRect: CGRect(x: x - 12, y: 40, width: 24, height: 14), cornerRadius: 7)
        sketch.fill(socket, top: N64Ink.port, bottom: N64Ink.portShade)
        context.stroke(socket, with: .color(.black.opacity(0.5)), lineWidth: 0.4)
        context.fill(
            Path(roundedRect: CGRect(x: x - 8, y: 44, width: 16, height: 6), cornerRadius: 3),
            with: .color(N64Ink.vent)
        )
        for offset in [-4.0, 0, 4] {
            context.fill(
                Path(roundedRect: CGRect(x: x + offset - 0.8, y: 45.4, width: 1.6, height: 3.2), cornerRadius: 0.6),
                with: .color(N64Ink.portShade)
            )
        }
    }
}

struct N64Slab: View {
    enum Kind {
        case hump
        case corner
        case lobe
    }

    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let sketch = ConsoleSketch(context: context, ink: N64Ink.lettering)
            switch kind {
            case .hump:
                sketch.fill(Path(bounds), top: N64Ink.shellLit, bottom: N64Ink.shellShade)
            case .corner:
                context.fill(
                    Path(bounds),
                    with: .linearGradient(
                        Gradient(colors: [N64Ink.shellShade, N64Ink.shell]),
                        startPoint: CGPoint(x: bounds.minX, y: bounds.midY),
                        endPoint: CGPoint(x: bounds.maxX, y: bounds.midY)
                    )
                )
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: 0.7 * size.height / N64Shape.height)),
                    with: .color(.white.opacity(0.2))
                )
            case .lobe:
                sketch.fill(Path(bounds), top: N64Ink.shellLit, bottom: N64Ink.shellShade)
                let scale = size.height / N64Shape.lobeHeight
                context.fill(
                    Path(CGRect(x: 0, y: size.height - 9 * scale, width: size.width, height: 9 * scale)),
                    with: .color(N64Ink.base)
                )
                context.fill(
                    Path(CGRect(x: 0, y: size.height - 19 * scale, width: size.width, height: 0.6 * scale)),
                    with: .color(.black.opacity(0.4))
                )
            }
        }
    }
}

struct N64LobeTop: View {
    let left: Bool

    var body: some View {
        Canvas { context, size in
            let reach = N64Shape.lobeReach + N64Shape.corner
            context.scaleBy(x: size.width / N64Shape.lobeWidth, y: size.height / reach)
            let sketch = ConsoleSketch(context: context, ink: N64Ink.lettering)
            let width = N64Shape.lobeWidth
            let bevel = N64Shape.lobeBevel
            let skirt = reach - bevel
            let corner = N64Shape.corner
            var outline = Path()
            var edge = Path()
            if left {
                outline.addLines([
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 0, y: skirt),
                    CGPoint(x: bevel, y: reach),
                    CGPoint(x: width, y: reach),
                    CGPoint(x: width, y: corner),
                    CGPoint(x: corner, y: corner),
                ])
                edge.addLines([CGPoint(x: 0, y: skirt), CGPoint(x: bevel, y: reach), CGPoint(x: width, y: reach)])
            } else {
                outline.addLines([
                    CGPoint(x: width, y: 0),
                    CGPoint(x: width, y: skirt),
                    CGPoint(x: width - bevel, y: reach),
                    CGPoint(x: 0, y: reach),
                    CGPoint(x: 0, y: corner),
                    CGPoint(x: width - corner, y: corner),
                ])
                edge.addLines([
                    CGPoint(x: 0, y: reach),
                    CGPoint(x: width - bevel, y: reach),
                    CGPoint(x: width, y: skirt),
                ])
            }
            outline.closeSubpath()
            sketch.fill(outline, top: N64Ink.shell, bottom: N64Ink.shellLit)
            context.stroke(edge, with: .color(.white.opacity(0.22)), lineWidth: 0.8)
        }
    }
}
