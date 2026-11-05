import SwiftUI

enum XboxInk {
    static let shell = MediaInk.gray(0x1D, 0x1F, 0x1D)
    static let shellLit = MediaInk.gray(0x3A, 0x3D, 0x3A)
    static let shellShade = MediaInk.gray(0x0B, 0x0C, 0x0B)
    static let jewel = MediaInk.gray(0x4F, 0xAC, 0x36)
    static let jewelLit = MediaInk.gray(0x8F, 0xD8, 0x6E)
    static let silver = MediaInk.gray(0xC9, 0xCC, 0xC8)
}

private func circle(_ center: CGPoint, _ radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
}

struct XboxTop: View {
    private static let jewelRadius = 27.0
    private static let jewelRing = 33.0
    private static let crossWidth = 58.0
    private static let ribPitch = 7.6
    private static let ribThickness = 3.2

    var body: some View {
        Canvas { context, size in
            let width = XboxShape.width
            let depth = XboxShape.depth
            context.scaleBy(x: size.width / width, y: size.height / depth)
            let center = CGPoint(x: width / 2, y: depth / 2)
            context.fill(Path(CGRect(x: 0, y: 0, width: width, height: depth)), with: .color(XboxInk.shell))
            for edge in [0.0, width] {
                var wedge = Path()
                wedge.move(to: CGPoint(x: edge, y: 0))
                wedge.addLine(to: center)
                wedge.addLine(to: CGPoint(x: edge, y: depth))
                wedge.closeSubpath()
                var ribbed = context
                ribbed.clip(to: wedge)
                for row in stride(from: 0.0, to: depth, by: Self.ribPitch) {
                    ribbed.fill(
                        Path(CGRect(x: 0, y: row, width: width, height: Self.ribThickness)),
                        with: .color(XboxInk.shellShade)
                    )
                }
            }
            var cross = Path()
            cross.move(to: .zero)
            cross.addLine(to: center)
            cross.addLine(to: CGPoint(x: width, y: 0))
            cross.move(to: CGPoint(x: 0, y: depth))
            cross.addLine(to: center)
            cross.addLine(to: CGPoint(x: width, y: depth))
            context.stroke(cross, with: .color(XboxInk.shellLit.opacity(0.55)), lineWidth: Self.crossWidth)
            context.fill(circle(center, Self.jewelRing), with: .color(XboxInk.shellShade))
            let jewel = 2 * Self.jewelRadius
            context.fill(
                circle(center, Self.jewelRadius),
                with: .radialGradient(
                    Gradient(colors: [XboxInk.jewelLit, XboxInk.jewel]),
                    center: CGPoint(
                        x: center.x - Self.jewelRadius + 0.4 * jewel,
                        y: center.y - Self.jewelRadius + 0.35 * jewel
                    ),
                    startRadius: 0,
                    endRadius: 0.7 * jewel
                )
            )
        }
    }
}

struct XboxSide: View {
    private static let ribLit = 5.0
    private static let ribShade = 3.0

    var body: some View {
        Canvas { context, size in
            let depth = XboxShape.depth
            let height = XboxShape.height
            context.scaleBy(x: size.width / depth, y: size.height / height)
            let lit = Self.ribLit / ConsoleStage.unit
            let shade = Self.ribShade / ConsoleStage.unit
            context.fill(Path(CGRect(x: 0, y: 0, width: depth, height: height)), with: .color(XboxInk.shell))
            for row in stride(from: lit, to: height, by: lit + shade) {
                context.fill(Path(CGRect(x: 0, y: row, width: depth, height: shade)), with: .color(XboxInk.shellShade))
            }
        }
    }
}

struct XboxFront: View {
    let led: Double

    private static let seamY = 30.0
    private static let blockLeft = 127.0
    private static let blockRight = 194.0
    private static let notchDepth = 18.0
    private static let ports: [(left: Double, right: Double)] = [(54, 77), (90, 113), (207, 230), (243, 267)]
    private static let portTop = 52.0
    private static let portHeight = 14.0
    private static let eject = CGPoint(x: 160.5, y: 46)
    private static let ejectRadius = 7.5
    private static let buttonRadius = 4.5

    var body: some View {
        Canvas { context, size in
            let width = XboxShape.width
            let height = XboxShape.height
            context.scaleBy(x: size.width / width, y: size.height / height)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: XboxInk.shellLit, location: 0),
                        .init(color: XboxInk.shell, location: 0.12),
                        .init(color: XboxInk.shellShade, location: 1),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: height)
                )
            )
            context.fill(Path(XboxShape.tray), with: .color(Palette.playBackground))
            var seam = Path()
            seam.move(to: CGPoint(x: 0, y: Self.seamY))
            seam.addLine(to: CGPoint(x: Self.blockLeft, y: Self.seamY))
            seam.move(to: CGPoint(x: Self.blockRight, y: Self.seamY))
            seam.addLine(to: CGPoint(x: width, y: Self.seamY))
            context.stroke(seam, with: .color(XboxInk.shellShade), lineWidth: 1.2)
            let block = Path(CGRect(x: Self.blockLeft, y: 0, width: Self.blockRight - Self.blockLeft, height: height))
            context.fill(block, with: .color(XboxInk.shell))
            context.stroke(block, with: .color(XboxInk.shellShade), lineWidth: 1)
            var notch = Path()
            notch.move(to: CGPoint(x: Self.blockLeft, y: 0))
            notch.addLine(to: CGPoint(x: (Self.blockLeft + Self.blockRight) / 2, y: Self.notchDepth))
            notch.addLine(to: CGPoint(x: Self.blockRight, y: 0))
            notch.closeSubpath()
            context.fill(notch, with: .color(XboxInk.shellLit.opacity(0.6)))
            for port in Self.ports {
                let shape = Path(
                    roundedRect: CGRect(
                        x: port.left,
                        y: Self.portTop,
                        width: port.right - port.left,
                        height: Self.portHeight
                    ),
                    cornerRadius: 5
                )
                context.fill(shape, with: .color(XboxInk.shellShade))
                context.stroke(shape, with: .color(XboxInk.shellLit), lineWidth: 0.8)
            }
            ejectButton(context)
            let power = XboxShape.power
            context.stroke(
                circle(power, XboxShape.ringRadius),
                with: .color((led > 0 ? GameSystem.xbox.powerLED : XboxInk.shellLit).opacity(0.4 + 0.6 * led)),
                lineWidth: XboxShape.ringWidth
            )
            context.fill(circle(power, Self.buttonRadius), with: .color(XboxInk.shellLit))
        }
    }

    private func ejectButton(_ context: GraphicsContext) {
        let center = Self.eject
        context.fill(circle(center, Self.ejectRadius), with: .color(XboxInk.silver))
        var glyph = Path()
        glyph.move(to: CGPoint(x: center.x - 4, y: center.y + 1.5))
        glyph.addLine(to: CGPoint(x: center.x + 4, y: center.y + 1.5))
        glyph.addLine(to: CGPoint(x: center.x, y: center.y - 3.5))
        glyph.closeSubpath()
        glyph.move(to: CGPoint(x: center.x - 4, y: center.y + 3.5))
        glyph.addLine(to: CGPoint(x: center.x + 4, y: center.y + 3.5))
        context.fill(glyph, with: .color(XboxInk.shell))
        context.stroke(glyph, with: .color(XboxInk.shell), lineWidth: 0.6)
    }
}

struct XboxTrayTop: View {
    let out: Double

    private static let hub = 0.09
    private static let hubEdge = 0.095
    private static let ring = 0.40
    private static let ringEdge = 0.41

    var body: some View {
        Canvas { context, size in
            let tray = XboxShape.tray
            let travel = XboxShape.trayTravel
            let reach = out * travel
            context.scaleBy(x: size.width / tray.width, y: size.height / reach)
            context.translateBy(x: 0, y: reach - travel)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: tray.width, height: travel)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: XboxInk.shellShade, location: 0),
                        .init(color: XboxInk.shellShade, location: Self.hub),
                        .init(color: XboxInk.shellLit, location: Self.hubEdge),
                        .init(color: XboxInk.shellLit, location: Self.ring),
                        .init(color: XboxInk.shell, location: Self.ringEdge),
                    ]),
                    center: CGPoint(x: tray.width / 2, y: travel / 2),
                    startRadius: 0,
                    endRadius: hypot(tray.width / 2, travel / 2)
                )
            )
        }
    }
}
