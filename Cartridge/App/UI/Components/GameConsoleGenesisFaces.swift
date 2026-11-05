import SwiftUI

enum GenesisInk {
    static let shellLit = MediaInk.gray(0x40, 0x40, 0x46)
    static let shell = MediaInk.gray(0x28, 0x28, 0x2D)
    static let shellShade = MediaInk.gray(0x14, 0x14, 0x17)
    static let discLit = MediaInk.gray(0x3A, 0x3A, 0x41)
    static let disc = MediaInk.gray(0x1E, 0x1E, 0x23)
    static let discWall = MediaInk.gray(0x0A, 0x0A, 0x0C)
    static let vent = MediaInk.gray(0x06, 0x06, 0x07)
    static let knob = MediaInk.gray(0x45, 0x45, 0x4B)
    static let reset = MediaInk.gray(0xE4, 0xE4, 0xE0)
    static let red = MediaInk.gray(0xB8, 0x14, 0x1C)
    static let ink = MediaInk.gray(0xDC, 0xDC, 0xE0)
    static let inkDim = MediaInk.gray(0x8C, 0x8C, 0x93)
    static let port = MediaInk.gray(0x07, 0x07, 0x08)
    static let flap = MediaInk.gray(0x1C, 0x1C, 0x21)
    static let ledOff = MediaInk.gray(0x4A, 0x0D, 0x10)
    static let cart = MediaInk.gray(0x26, 0x26, 0x2A)
    static let cartShade = MediaInk.gray(0x12, 0x12, 0x14)
}

private func slotHole(originX: Double, originZ: Double, grow: Double = 0) -> Path {
    let slot = TopLoader.genesis.slot
    return Path(
        roundedRect: CGRect(
            x: slot.left - originX - grow,
            y: slot.back - originZ - grow,
            width: slot.right - slot.left + 2 * grow,
            height: slot.front - slot.back + 2 * grow
        ),
        cornerRadius: grow > 0 ? 4 : 1.5
    )
}

struct GenesisDeck: View {
    let power: Double

    var body: some View {
        Canvas { context, size in
            let width = GenesisShape.width
            let depth = GenesisShape.deckDepth
            context.scaleBy(x: size.width / width, y: size.height / depth)
            let sketch = ConsoleSketch(context: context, ink: GenesisInk.ink)
            let hole = slotHole(originX: 0, originZ: -GenesisShape.depth)
            var shell = Path(CGRect(x: 0, y: 0, width: width, height: depth))
            shell.addPath(hole)
            sketch.fill(shell, top: GenesisInk.shell, bottom: GenesisInk.shellLit, eoFill: true)
            let radius = GenesisShape.ringRadius + 1
            let center = GenesisShape.ringCenter
            var wall = Path(
                ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y + GenesisShape.depth - radius,
                    width: 2 * radius,
                    height: 2 * radius
                )
            )
            wall.addPath(hole)
            context.fill(wall, with: .color(GenesisInk.discWall), style: FillStyle(eoFill: true))
            vent(sketch)
            panel(sketch)
            sketch.rect(0, depth - 0.6, width, 0.6, .white.opacity(0.22))
        }
    }

    private func vent(_ sketch: ConsoleSketch) {
        let grille = Path(roundedRect: CGRect(x: 32, y: 20, width: 70, height: 64), cornerRadius: 3)
        sketch.context.fill(grille, with: .color(.black.opacity(0.4)))
        sketch.context.stroke(grille, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
        for slat in 0..<16 {
            let y = 25 + Double(slat) * 3.6
            sketch.context.fill(
                Path(roundedRect: CGRect(x: 37, y: y, width: 60, height: 1.7), cornerRadius: 0.5),
                with: .color(GenesisInk.vent)
            )
            sketch.rect(37, y + 1.7, 60, 0.5, .white.opacity(0.07))
        }
    }

    private func panel(_ sketch: ConsoleSketch) {
        let context = sketch.context
        let plate = Path(roundedRect: CGRect(x: 24, y: 112, width: 100, height: 74), cornerRadius: 4)
        context.fill(plate, with: .color(.black.opacity(0.32)))
        context.stroke(plate, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
        context.fill(
            Path(roundedRect: CGRect(x: 38, y: 120, width: 4, height: 48), cornerRadius: 1),
            with: .color(GenesisInk.vent)
        )
        knob(sketch, CGRect(x: 33, y: 146, width: 14, height: 10), radius: 1.4, ridges: [])
        for tick in 0..<6 {
            sketch.rect(44, 121 + Double(tick) * 8, 3, 0.5, GenesisInk.inkDim)
        }
        context.fill(
            Path(roundedRect: CGRect(x: 64, y: 125, width: 36, height: 6), cornerRadius: 1),
            with: .color(GenesisInk.vent)
        )
        knob(sketch, CGRect(x: 86 + power, y: 120, width: 12, height: 16), radius: 1.6, ridges: [124, 127, 130, 133])
        sketch.word("ON", size: 3.6, tracking: 0.3, at: CGPoint(x: 66, y: 143.7))
        sketch.word("OFF", size: 3.6, tracking: 0.3, at: CGPoint(x: 98, y: 143.7))
        context.fill(
            Path(roundedRect: CGRect(x: 66, y: 157, width: 20, height: 8), cornerRadius: 1),
            with: .color(GenesisInk.reset)
        )
        sketch.rect(66, 164.2, 20, 0.8, .black.opacity(0.25))
        sketch.word("RESET", size: 3.2, tracking: 0.3, at: CGPoint(x: 76, y: 173.9))
        sketch.word("VOLUME", size: 3.2, tracking: 0.3, at: CGPoint(x: 40, y: 178.9))
    }

    private func knob(_ sketch: ConsoleSketch, _ rect: CGRect, radius: Double, ridges: [Double]) {
        let key = Path(roundedRect: rect, cornerRadius: radius)
        sketch.fill(key, top: GenesisInk.knob, bottom: GenesisInk.shellShade)
        sketch.context.stroke(key, with: .color(.black.opacity(0.6)), lineWidth: 0.4)
        sketch.rect(rect.minX + 1, rect.minY + 0.6, rect.width - 2, 0.6, .white.opacity(0.25))
        for y in ridges {
            sketch.rect(rect.minX + 2, y, rect.width - 4, 0.6, .black.opacity(0.45))
        }
    }
}

struct GenesisRing: View {
    let led: Double

    var body: some View {
        Canvas { context, size in
            let diameter = 2 * GenesisShape.ringRadius
            let unit = size.width / diameter
            let glow = context
            context.scaleBy(x: unit, y: size.height / diameter)
            let sketch = ConsoleSketch(context: context, ink: GenesisInk.ink)
            let origin = GenesisShape.ringOrigin
            let hole = slotHole(originX: origin.x, originZ: origin.y)
            let disc = Path(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            var face = disc
            face.addPath(hole)
            sketch.fill(face, top: GenesisInk.disc, bottom: GenesisInk.discLit, eoFill: true)
            rings(sketch, diameter: diameter)
            var bezel = slotHole(originX: origin.x, originZ: origin.y, grow: 4)
            bezel.addPath(hole)
            context.fill(bezel, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
            context.stroke(hole, with: .color(.black.opacity(0.8)), lineWidth: 0.8)
            lip(sketch, disc: disc, diameter: diameter)
            band(sketch, disc: disc, diameter: diameter)
            ConsoleLED(
                rect: GenesisShape.led,
                off: GenesisInk.ledOff,
                shine: .white.opacity(0.7),
                color: GameSystem.genesis.powerLED
            )
            .draw(led, in: context, glow: glow, unit: unit)
            context.stroke(disc, with: .color(.white.opacity(0.2)), lineWidth: 0.7)
        }
    }

    private func rings(_ sketch: ConsoleSketch, diameter: Double) {
        let center = diameter / 2
        for (radius, color, width) in [(62.0, Color.black.opacity(0.7), 0.9), (62.8, Color.white.opacity(0.09), 0.5)] {
            let groove = CGRect(x: center - radius, y: center - radius, width: 2 * radius, height: 2 * radius)
            sketch.context.stroke(Path(ellipseIn: groove), with: .color(color), lineWidth: width)
        }
    }

    private func lip(_ sketch: ConsoleSketch, disc: Path, diameter: Double) {
        let radius = GenesisShape.ringRadius
        let seam = 84.0
        let half = (radius * radius - (seam - radius) * (seam - radius)).squareRoot()
        let below = disc.intersection(Path(CGRect(x: 0, y: seam, width: diameter, height: diameter - seam)))
        sketch.context.fill(below, with: .color(.white.opacity(0.05)))
        sketch.rect(radius - half + 2, seam - 0.4, 2 * half - 4, 0.8, .black.opacity(0.7))
        sketch.rect(radius - half + 2, seam + 0.55, 2 * half - 4, 0.5, .white.opacity(0.12))
    }

    private func band(_ sketch: ConsoleSketch, disc: Path, diameter: Double) {
        let radius = GenesisShape.ringRadius
        sketch.word("16-BIT", size: 9, tracking: 0.3, at: CGPoint(x: radius, y: 100.85))
        let stripe = disc.intersection(Path(CGRect(x: 0, y: 113, width: diameter, height: 11)))
        sketch.context.fill(stripe, with: .color(GenesisInk.red))
        let edge = disc.intersection(Path(CGRect(x: 0, y: 113, width: diameter, height: 0.6)))
        sketch.context.fill(edge, with: .color(.white.opacity(0.25)))
        sketch.word("POWER", size: 3.4, tracking: 0.3, at: CGPoint(x: radius - 10.5, y: 119))
        sketch.word("ON", size: 3.4, tracking: 0.3, at: CGPoint(x: radius + 5.5, y: 119))
    }
}

struct GenesisChamfer: View {
    let length: Double

    var body: some View {
        Canvas { context, size in
            let width = GenesisShape.width
            context.scaleBy(x: size.width / width, y: size.height / length)
            let sketch = ConsoleSketch(context: context, ink: GenesisInk.ink)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: length)),
                top: GenesisInk.shellLit,
                bottom: GenesisInk.shellShade
            )
            sketch.rect(0, 0, width, 0.7, .white.opacity(0.3))
        }
    }
}

struct GenesisFront: View {
    var body: some View {
        Canvas { context, size in
            let width = GenesisShape.width
            let height = GenesisShape.frontHeight
            context.scaleBy(x: size.width / width, y: size.height / height)
            let sketch = ConsoleSketch(context: context, ink: GenesisInk.inkDim)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                top: GenesisInk.shell,
                bottom: GenesisInk.shellShade
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: 26.4, y: 10.4, width: 7.2, height: 7.2)),
                with: .color(.white.opacity(0.16)),
                lineWidth: 0.6
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 27.6, y: 11.6, width: 4.8, height: 4.8)),
                with: .color(GenesisInk.port)
            )
            sketch.word("PHONES", size: 2.8, tracking: 0.3, at: CGPoint(x: 30, y: 23))
            for (index, x) in [160.0, 210].enumerated() {
                port(sketch, x: x)
                sketch.word("CONTROL \(index + 1)", size: 2.8, tracking: 0.3, at: CGPoint(x: x + 13, y: 27))
            }
            sketch.rect(0, height - 6, width, 6, .black.opacity(0.35))
            sketch.rect(0, height - 6, width, 0.5, .white.opacity(0.08))
            sketch.rect(0, 0, width, 0.6, .white.opacity(0.2))
        }
    }

    private func port(_ sketch: ConsoleSketch, x: Double) {
        var socket = Path()
        socket.addLines([
            CGPoint(x: x, y: 11),
            CGPoint(x: x + 26, y: 11),
            CGPoint(x: x + 24, y: 21),
            CGPoint(x: x + 2, y: 21),
        ])
        socket.closeSubpath()
        sketch.context.fill(socket, with: .color(GenesisInk.port))
        sketch.context.stroke(socket, with: .color(.white.opacity(0.14)), lineWidth: 0.5)
        for (row, count, offset) in [(14.4, 5, 5.0), (17.8, 4, 7.0)] {
            for pin in 0..<count {
                let center = CGPoint(x: x + offset + Double(pin) * 4, y: row)
                sketch.context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 0.7, y: center.y - 0.7, width: 1.4, height: 1.4)),
                    with: .color(.white.opacity(0.22))
                )
            }
        }
    }
}
