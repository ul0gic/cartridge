import SwiftUI

enum SNESInk {
    static let shellLit = MediaInk.gray(0xDD, 0xDC, 0xE2)
    static let shell = MediaInk.gray(0xCD, 0xCC, 0xD3)
    static let shellShade = MediaInk.gray(0xB3, 0xB2, 0xBB)
    static let base = MediaInk.gray(0x9C, 0x9B, 0xA5)
    static let baseShade = MediaInk.gray(0x7D, 0x7C, 0x86)
    static let trough = MediaInk.gray(0xB6, 0xB5, 0xBE)
    static let slider = MediaInk.gray(0x61, 0x52, 0xC4)
    static let sliderShade = MediaInk.gray(0x43, 0x37, 0x9C)
    static let lettering = MediaInk.gray(0x6D, 0x6C, 0x77)
    static let port = MediaInk.gray(0x26, 0x26, 0x2C)
    static let flap = MediaInk.gray(0x45, 0x45, 0x4D)
    static let ledOff = MediaInk.gray(0x3A, 0x17, 0x17)
    static let cart = MediaInk.gray(0xC9, 0xC7, 0xC1)
    static let cartShade = MediaInk.gray(0xA4, 0xA2, 0x9C)
}

struct SNESRearTop: View {
    var body: some View {
        Canvas { context, size in
            let width = SNESShape.width
            let depth = SNESShape.rearDepth
            context.scaleBy(x: size.width / width, y: size.height / depth)
            let sketch = ConsoleSketch(context: context, ink: SNESInk.lettering)
            let slot = TopLoader.snes.slot
            let opening = CGRect(
                x: slot.left,
                y: slot.back + SNESShape.depth,
                width: slot.right - slot.left,
                height: slot.front - slot.back
            )
            let hole = Path(roundedRect: opening, cornerRadius: 1.5)
            var shell = Path(CGRect(x: 0, y: 0, width: width, height: depth))
            shell.addPath(hole)
            sketch.fill(shell, top: SNESInk.shell, bottom: SNESInk.shellLit, eoFill: true)
            let housing = Path(
                roundedRect: CGRect(x: 16, y: opening.minY - 16, width: width - 32, height: opening.height + 32),
                cornerRadius: 8
            )
            var raised = housing
            raised.addPath(hole)
            sketch.fill(raised, top: SNESInk.shellLit, bottom: SNESInk.shell, eoFill: true)
            context.stroke(housing, with: .color(.black.opacity(0.22)), lineWidth: 0.7)
            sketch.rect(24, opening.minY - 15.8, width - 48, 0.6, .white.opacity(0.7))
            context.stroke(hole, with: .color(.black.opacity(0.5)), lineWidth: 0.9)
            sketch.rect(opening.minX, opening.maxY + 0.5, opening.width, 0.6, .white.opacity(0.6))
            sketch.rect(0, depth - 10, width, 0.7, .black.opacity(0.16))
            sketch.rect(0, depth - 9.3, width, 0.5, .white.opacity(0.4))
            sketch.rect(0, depth - 0.7, width, 0.7, .white.opacity(0.6))
        }
    }
}

struct SNESStep: View {
    var body: some View {
        Canvas { context, size in
            let width = SNESShape.width
            let height = SNESShape.step
            context.scaleBy(x: size.width / width, y: size.height / height)
            let sketch = ConsoleSketch(context: context, ink: SNESInk.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                top: SNESInk.shellLit,
                bottom: SNESInk.shellShade
            )
            let plate = Path(roundedRect: CGRect(x: 62, y: 4, width: 76, height: 10), cornerRadius: 1.6)
            context.fill(plate, with: .color(.black.opacity(0.06)))
            context.stroke(plate, with: .color(.black.opacity(0.2)), lineWidth: 0.5)
            sketch.rect(63, 13.6, 74, 0.5, .white.opacity(0.4))
            sketch.rect(0, 0, width, 0.6, .white.opacity(0.55))
        }
    }
}

struct SNESDeck: View {
    let power: Double
    let led: Double

    var body: some View {
        Canvas { context, size in
            let width = SNESShape.width
            let depth = SNESShape.deckDepth
            let unit = size.width / width
            let glow = context
            context.scaleBy(x: unit, y: size.height / depth)
            let sketch = ConsoleSketch(context: context, ink: SNESInk.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: depth)),
                top: SNESInk.shell,
                bottom: SNESInk.shellLit
            )
            sketch.fill(Path(CGRect(x: 80, y: 0, width: 40, height: depth)), top: SNESInk.trough, bottom: SNESInk.shell)
            sketch.rect(79.4, 0, 0.6, depth, .black.opacity(0.25))
            sketch.rect(120, 0, 0.6, depth, .white.opacity(0.5))
            let plate = Path(roundedRect: CGRect(x: 88, y: 6, width: 24, height: 20), cornerRadius: 2)
            context.fill(plate, with: .color(SNESInk.shellShade))
            context.stroke(plate, with: .color(.black.opacity(0.3)), lineWidth: 0.4)
            sketch.rect(89, 6.5, 22, 0.6, .white.opacity(0.4))
            for (index, x) in SNESShape.switches.enumerated() {
                slider(sketch, x: x, travel: index == 0 ? power : 0)
            }
            sketch.word("POWER", size: 4.2, tracking: 0.3, at: CGPoint(x: SNESShape.switches[0] + 14, y: 97.5))
            sketch.word("RESET", size: 4.2, tracking: 0.3, at: CGPoint(x: SNESShape.switches[1] + 14, y: 97.5))
            ConsoleLED(
                rect: SNESShape.led,
                off: SNESInk.ledOff,
                shine: .white.opacity(0.7),
                color: GameSystem.snes.powerLED
            )
            .draw(led, in: context, glow: glow, unit: unit)
            sketch.rect(0, 0, width, 0.8, .black.opacity(0.3))
            sketch.rect(0, depth - 0.7, width, 0.7, .white.opacity(0.6))
        }
    }

    private func slider(_ sketch: ConsoleSketch, x: Double, travel: Double) {
        let context = sketch.context
        context.fill(
            Path(roundedRect: CGRect(x: x - 2, y: 30, width: 32, height: 58), cornerRadius: 3),
            with: .color(.black.opacity(0.2))
        )
        sketch.rect(x - 2, 87.4, 32, 0.6, .white.opacity(0.5))
        let knob = CGRect(x: x, y: 62 + travel, width: 28, height: 23)
        let key = Path(roundedRect: knob, cornerRadius: 2.6)
        sketch.fill(key, top: SNESInk.slider, bottom: SNESInk.sliderShade)
        context.stroke(key, with: .color(.black.opacity(0.45)), lineWidth: 0.4)
        context.fill(
            Path(roundedRect: CGRect(x: x + 1, y: knob.minY + 0.6, width: 26, height: 0.8), cornerRadius: 0.4),
            with: .color(.white.opacity(0.45))
        )
        for y in [68.0, 72, 76, 80] {
            sketch.rect(x + 6, y + travel, 16, 0.7, .black.opacity(0.25))
        }
    }
}

struct SNESFront: View {
    var body: some View {
        Canvas { context, size in
            let width = SNESShape.width
            let height = SNESShape.height - SNESShape.step
            context.scaleBy(x: size.width / width, y: size.height / height)
            let sketch = ConsoleSketch(context: context, ink: SNESInk.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                top: SNESInk.shellLit,
                bottom: SNESInk.shellShade
            )
            for y in [5.0, 9, 13] {
                sketch.rect(0, y, width, 0.6, .black.opacity(0.14))
                sketch.rect(0, y + 0.6, width, 0.4, .white.opacity(0.35))
            }
            for (index, x) in SNESShape.ports.enumerated() {
                port(sketch, x: x)
                sketch.word("\(index + 1)", size: 3.6, tracking: 0.3, at: CGPoint(x: x + 13, y: 34.7))
            }
            sketch.fill(
                Path(CGRect(x: 0, y: 40, width: width, height: height - 40)),
                top: SNESInk.base,
                bottom: SNESInk.baseShade
            )
            sketch.rect(0, 40, width, 0.8, .black.opacity(0.4))
            sketch.rect(0, 0, width, 0.6, .white.opacity(0.55))
        }
    }

    private func port(_ sketch: ConsoleSketch, x: Double) {
        var socket = Path()
        socket.addLines([CGPoint(x: x + 5, y: 18), CGPoint(x: x + 26, y: 18), CGPoint(x: x + 26, y: 30)])
        socket.addLine(to: CGPoint(x: x + 5, y: 30))
        socket.addQuadCurve(to: CGPoint(x: x, y: 24), control: CGPoint(x: x, y: 30))
        socket.addQuadCurve(to: CGPoint(x: x + 5, y: 18), control: CGPoint(x: x, y: 18))
        socket.closeSubpath()
        sketch.context.fill(socket, with: .color(SNESInk.port))
        for pin in 0..<7 {
            sketch.rect(x + 4 + Double(pin) * 3, 23.2, 1.4, 1.6, .white.opacity(0.25))
        }
    }
}
