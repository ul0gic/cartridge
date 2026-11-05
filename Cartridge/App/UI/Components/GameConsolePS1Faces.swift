import SwiftUI

enum PS1Ink {
    static let shellLit = MediaInk.gray(0xD3, 0xD4, 0xD8)
    static let shell = MediaInk.gray(0xC2, 0xC4, 0xC8)
    static let shellShade = MediaInk.gray(0xA6, 0xA8, 0xAD)
    static let base = MediaInk.gray(0x8F, 0x91, 0x96)
    static let button = MediaInk.gray(0xCB, 0xCD, 0xD1)
    static let buttonShade = MediaInk.gray(0xA2, 0xA4, 0xA9)
    static let lettering = MediaInk.gray(0x67, 0x6A, 0x71)
    static let letteringBlue = MediaInk.gray(0x3B, 0x5E, 0xA6)
    static let lidLit = MediaInk.gray(0xD0, 0xD2, 0xD6)
    static let lid = MediaInk.gray(0xB9, 0xBB, 0xC0)
    static let lidUnder = MediaInk.gray(0x8F, 0x91, 0x96)
    static let port = MediaInk.gray(0x2B, 0x2C, 0x31)
    static let lens = MediaInk.gray(0x36, 0x47, 0x7A)
    static let ledOff = MediaInk.gray(0x17, 0x3A, 0x22)
    static let pit = MediaInk.gray(0x05, 0x05, 0x06)
    static let pitLit = MediaInk.gray(0x1D, 0x1D, 0x21)
}

private func circle(_ center: CGPoint, _ radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
}

struct PS1Top: View {
    let open: Double
    let power: Double
    let led: Double

    var body: some View {
        Canvas { context, size in
            let width = PS1Shape.width
            let depth = PS1Shape.depth
            let unit = size.width / width
            let glow = context
            context.scaleBy(x: unit, y: size.height / depth)
            let sketch = ConsoleSketch(context: context, ink: PS1Ink.lettering)
            let lid = CGPoint(x: PS1Shape.lidX, y: PS1Shape.lidZ + depth)
            var shell = Path(CGRect(x: 0, y: 0, width: width, height: depth))
            shell.addPath(circle(lid, PS1Shape.hole))
            sketch.fill(shell, top: PS1Ink.shell, bottom: PS1Ink.shellLit, eoFill: true)
            context.stroke(circle(lid, PS1Shape.lidRadius + 0.8), with: .color(.black.opacity(0.3)), lineWidth: 1)
            let band = PS1Shape.band
            sketch.rect(0, band - 0.35, width, 0.7, .black.opacity(0.22))
            sketch.rect(0, band + 0.45, width, 0.5, .white.opacity(0.45))
            for x in [70.0, 222] {
                sketch.rect(x - 0.35, band + 0.7, 0.7, depth - band - 0.7, .black.opacity(0.22))
                sketch.rect(x + 0.45, band + 1, 0.5, depth - band - 1, .white.opacity(0.4))
            }
            button(sketch, at: CGPoint(x: 42, y: 110), radius: 7, word: nil, press: 1)
            sketch.word("RESET", size: 3, tracking: 0.3, at: CGPoint(x: 42, y: 121.9))
            button(sketch, at: CGPoint(x: 44, y: 150), radius: 14, word: "POWER", press: power)
            button(sketch, at: CGPoint(x: 246, y: 154), radius: 14, word: "OPEN", press: open)
            ConsoleLED(
                rect: PS1Shape.led,
                off: PS1Ink.ledOff,
                shine: .white.opacity(0.7),
                color: GameSystem.ps1.powerLED
            )
            .draw(led, in: context, glow: glow, unit: unit)
            sketch.rect(0, depth - 0.7, width, 0.7, .white.opacity(0.6))
        }
    }

    private func button(_ sketch: ConsoleSketch, at center: CGPoint, radius: Double, word: String?, press: Double) {
        var context = sketch.context
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: press, y: press)
        let cap = ConsoleSketch(context: context, ink: PS1Ink.letteringBlue)
        context.fill(circle(.zero, radius + 0.8), with: .color(.black.opacity(0.18)))
        cap.fill(circle(.zero, radius), top: PS1Ink.button, bottom: PS1Ink.buttonShade)
        context.stroke(circle(.zero, radius), with: .color(.black.opacity(0.25)), lineWidth: 0.4)
        var shine = Path()
        shine.addArc(
            center: CGPoint(x: 0, y: 0.15 * radius),
            radius: radius,
            startAngle: .degrees(216.87),
            endAngle: .degrees(323.13),
            clockwise: false
        )
        context.stroke(shine, with: .color(.white.opacity(0.6)), lineWidth: 0.6)
        if let word {
            cap.word(word, size: 3.6, tracking: 0.3, at: .zero)
        }
    }
}

struct PS1Well: View {
    var body: some View {
        Canvas { context, size in
            let radius = PS1Shape.lidRadius
            let side = 2 * radius
            context.scaleBy(x: size.width / side, y: size.height / side)
            let sketch = ConsoleSketch(context: context, ink: PS1Ink.lettering)
            let center = CGPoint(x: radius, y: radius)
            sketch.rect(0, 0, side, side, PS1Ink.pit)
            context.fill(circle(center, PS1Shape.hole), with: .color(PS1Ink.pitLit))
            let sled = Path(roundedRect: CGRect(x: 18, y: radius + 4, width: 18, height: 38), cornerRadius: 3)
            context.fill(sled, with: .color(PS1Ink.pit))
            context.stroke(sled, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
            context.fill(circle(CGPoint(x: 27, y: radius + 22), 3.6), with: .color(PS1Ink.lens))
            context.fill(circle(CGPoint(x: 26, y: radius + 21), 1.1), with: .color(.white.opacity(0.6)))
            context.stroke(circle(center, 15), with: .color(.white.opacity(0.08)), lineWidth: 1.2)
            sketch.fill(circle(center, 9), top: PS1Ink.button, bottom: PS1Ink.buttonShade)
            context.fill(circle(center, 2.6), with: .color(PS1Ink.buttonShade))
        }
    }
}

struct PS1LidTop: View {
    var body: some View {
        Canvas { context, size in
            let radius = PS1Shape.lidRadius
            context.scaleBy(x: size.width / (2 * radius), y: size.height / (2 * radius))
            let sketch = ConsoleSketch(context: context, ink: PS1Ink.lettering)
            let center = CGPoint(x: radius, y: radius)
            sketch.fill(circle(center, radius), top: PS1Ink.lid, bottom: PS1Ink.lidLit)
            context.stroke(circle(center, radius - 7), with: .color(.black.opacity(0.08)), lineWidth: 1)
            var rim = Path()
            rim.addArc(
                center: center,
                radius: radius - 0.5,
                startAngle: .degrees(180),
                endAngle: .zero,
                clockwise: false
            )
            context.stroke(rim, with: .color(.white.opacity(0.5)), lineWidth: 0.8)
            context.stroke(circle(center, radius), with: .color(.black.opacity(0.25)), lineWidth: 0.6)
        }
    }
}

struct PS1LidUnder: View {
    var body: some View {
        Canvas { context, size in
            let radius = PS1Shape.lidRadius
            context.scaleBy(x: size.width / (2 * radius), y: size.height / (2 * radius))
            let center = CGPoint(x: radius, y: radius)
            context.fill(circle(center, radius), with: .color(PS1Ink.lidUnder))
            context.stroke(circle(center, radius - 4), with: .color(.black.opacity(0.18)), lineWidth: 1.2)
            context.fill(circle(center, 10), with: .color(.black.opacity(0.12)))
            context.stroke(circle(center, 10), with: .color(.white.opacity(0.25)), lineWidth: 0.6)
            context.fill(circle(center, 4), with: .color(.black.opacity(0.2)))
        }
    }
}

struct PS1Front: View {
    var body: some View {
        Canvas { context, size in
            let width = PS1Shape.width
            let height = PS1Shape.height
            context.scaleBy(x: size.width / width, y: size.height / height)
            let sketch = ConsoleSketch(context: context, ink: PS1Ink.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                top: PS1Ink.shellLit,
                bottom: PS1Ink.shellShade
            )
            sketch.rect(0, 12, width, 0.7, .black.opacity(0.2))
            sketch.rect(0, 12.7, width, 0.5, .white.opacity(0.4))
            sketch.rect(0, height - 7, width, 7, PS1Ink.base)
            sketch.rect(0, 0, width, 0.7, .white.opacity(0.6))
        }
    }
}

struct PS1BlockTop: View {
    var body: some View {
        Canvas { context, size in
            let width = PS1Shape.blockWidth
            let reach = PS1Shape.blockReach
            context.scaleBy(x: size.width / width, y: size.height / reach)
            let sketch = ConsoleSketch(context: context, ink: PS1Ink.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: reach)),
                top: PS1Ink.shell,
                bottom: PS1Ink.shellLit
            )
            for (index, x) in PS1BlockFront.columns.enumerated() {
                sketch.word("\(index + 1)", size: 5, tracking: 0.3, at: CGPoint(x: x, y: 5.6))
            }
            sketch.rect(0, reach - 0.6, width, 0.6, .white.opacity(0.6))
        }
    }
}

struct PS1BlockFront: View {
    static let columns = [21.0, 64]

    var body: some View {
        Canvas { context, size in
            let width = PS1Shape.blockWidth
            let height = PS1Shape.blockHeight
            context.scaleBy(x: size.width / width, y: size.height / height)
            let sketch = ConsoleSketch(context: context, ink: PS1Ink.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                top: PS1Ink.shellLit,
                bottom: PS1Ink.shellShade
            )
            for x in Self.columns {
                context.fill(
                    Path(roundedRect: CGRect(x: x - 15, y: 6, width: 30, height: 5), cornerRadius: 1),
                    with: .color(PS1Ink.port)
                )
                sketch.rect(x - 15, 10.6, 30, 0.5, .white.opacity(0.4))
                context.fill(
                    Path(roundedRect: CGRect(x: x - 16, y: 17, width: 32, height: 12), cornerRadius: 4),
                    with: .color(PS1Ink.port)
                )
                for pin in 0..<9 {
                    sketch.rect(x - 12 + Double(pin) * 3, 22, 1.2, 2, .white.opacity(0.25))
                }
            }
            sketch.rect(0, height - 7, width, 7, PS1Ink.base)
        }
    }
}
