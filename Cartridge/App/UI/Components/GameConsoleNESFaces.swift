import SwiftUI

enum NESInk {
    static let shellLit = MediaInk.gray(0xDA, 0xDA, 0xD6)
    static let shell = MediaInk.gray(0xCB, 0xCB, 0xC7)
    static let shellShade = MediaInk.gray(0xB4, 0xB4, 0xB0)
    static let base = MediaInk.gray(0x8E, 0x8E, 0x91)
    static let baseShade = MediaInk.gray(0x6F, 0x6F, 0x72)
    static let band = MediaInk.gray(0x2B, 0x2B, 0x2E)
    static let bandShade = MediaInk.gray(0x14, 0x14, 0x16)
    static let ridge = MediaInk.gray(0xC6, 0xC6, 0xC2)
    static let groove = MediaInk.gray(0x8B, 0x8B, 0x88)
    static let button = MediaInk.gray(0xA1, 0xA1, 0xA4)
    static let buttonShade = MediaInk.gray(0x7A, 0x7A, 0x7D)
    static let lettering = MediaInk.gray(0xC8, 0x24, 0x2C)
    static let port = MediaInk.gray(0x0A, 0x0A, 0x0B)
    static let portFace = MediaInk.gray(0x2E, 0x2E, 0x31)
    static let pin = MediaInk.gray(0x02, 0x02, 0x03)
    static let doorInner = MediaInk.gray(0x6A, 0x6A, 0x68)
    static let cavity = MediaInk.gray(0x05, 0x05, 0x06)
    static let cavityLit = MediaInk.gray(0x26, 0x26, 0x2A)
    static let ledOff = MediaInk.gray(0x3A, 0x17, 0x17)
    static let ledShine = MediaInk.gray(0xFF, 0xDC, 0xDC)
    static let cartTail = [MediaInk.gray(0xB0, 0xB0, 0xAD), MediaInk.gray(0x8A, 0x8A, 0x87)]
    static let cartSide = [MediaInk.gray(0x8A, 0x8A, 0x87), MediaInk.gray(0x74, 0x74, 0x71)]
}

struct NESConsoleUnder: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera

    var body: some View {
        let mm = ConsoleStage.unit
        let floor = NESShape.cavityFloor * mm
        let depth = NESShape.cavityDepth * mm
        let left = NESShape.doorLeft * mm
        let width = NESShape.doorWidth * mm
        let wall = CGSize(width: depth, height: floor - NESStage.lip)
        ZStack(alignment: .topLeading) {
            ConsoleFloorShadow(rig: rig, camera: camera, depth: NESShape.depth, height: NESShape.height)
            ProjectedFace(
                face: rig.face(
                    SIMD3(left, floor, -depth),
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    CGSize(width: width, height: depth)
                ),
                camera: camera
            ) {
                LinearGradient(
                    stops: [.init(color: NESInk.cavity, location: 0.4), .init(color: NESInk.cavityLit, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(left, NESStage.lip, -depth),
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    CGSize(width: width, height: wall.height)
                ),
                camera: camera
            ) {
                NESInk.cavity
            }
            ProjectedFace(
                face: rig.face(SIMD3(left, NESStage.lip, 0), -ConsoleAxis.front, ConsoleAxis.down, wall),
                camera: camera
            ) {
                wallShade(mouth: .leading)
            }
            ProjectedFace(
                face: rig.face(SIMD3(left + width, NESStage.lip, -depth), ConsoleAxis.front, ConsoleAxis.down, wall),
                camera: camera
            ) {
                wallShade(mouth: .trailing)
            }
        }
    }

    private func wallShade(mouth: UnitPoint) -> some View {
        LinearGradient(
            stops: [.init(color: NESInk.cavityLit, location: 0), .init(color: NESInk.cavity, location: 0.7)],
            startPoint: mouth,
            endPoint: UnitPoint(x: 1 - mouth.x, y: mouth.y)
        )
    }
}

struct NESConsoleShell: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let power: Double
    let led: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, 0, -NESShape.depth * ConsoleStage.unit),
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(NESShape.width, NESShape.depth)
                ),
                camera: camera,
                shade: 0.02
            ) {
                NESTopFace()
            }
            ProjectedFace(
                face: rig.face(
                    .zero,
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(NESShape.width, NESShape.height)
                ),
                camera: camera,
                shade: 0.1
            ) {
                NESFrontFace(power: power, led: led)
            }
        }
    }
}

struct NESConsoleDoor: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let door: Double
    let shade: Double

    var body: some View {
        let mm = ConsoleStage.unit
        let hinge = rig.hinge(SIMD3(NESShape.doorLeft, 0, -NESShape.strip), door)
        let width = NESShape.doorWidth * mm
        let strip = NESShape.strip * mm
        let height = NESShape.split * mm
        ZStack(alignment: .topLeading) {
            ProjectedFace(
                face: hinge.face(
                    SIMD3(0, 0, strip),
                    ConsoleAxis.right,
                    -ConsoleAxis.front,
                    CGSize(width: width, height: strip)
                ),
                camera: camera,
                shade: 0.1
            ) {
                LinearGradient(
                    colors: [NESInk.doorInner, NESInk.doorInner.mix(with: .black, by: 0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            ProjectedFace(
                face: hinge.face(
                    .zero,
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    CGSize(width: width, height: strip + NESStage.seam)
                ),
                camera: camera,
                shade: 0.02
            ) {
                NESDoorStrip()
            }
            ProjectedFace(
                face: hinge.face(
                    SIMD3(0, -NESStage.seam, strip),
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    CGSize(width: width, height: height + NESStage.seam)
                ),
                camera: camera,
                shade: shade
            ) {
                NESDoorFront()
            }
        }
    }
}

struct NESCartFaces: View {
    let cart: NESCartRig
    let camera: ConsoleCamera
    let edges: Double
    let title: String
    let art: TileArt

    var body: some View {
        let size = ConsoleStage.size(NESCart.width, NESCart.height)
        let thickness = NESCart.thickness * ConsoleStage.unit
        let side = CGSize(width: thickness, height: NESCart.sideLength * ConsoleStage.unit)
        let tail = CGSize(width: size.width, height: thickness)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ProjectedFace(
                    face: cart.face(SIMD3(0, 0, -thickness), ConsoleAxis.right, ConsoleAxis.front, tail),
                    camera: camera,
                    shade: 0.08
                ) {
                    LinearGradient(colors: NESInk.cartTail, startPoint: .top, endPoint: .bottom)
                }
                ProjectedFace(
                    face: cart.face(SIMD3(0, 0, -thickness), ConsoleAxis.front, ConsoleAxis.down, side),
                    camera: camera,
                    shade: 0.35
                ) {
                    LinearGradient(colors: NESInk.cartSide, startPoint: .leading, endPoint: .trailing)
                }
                ProjectedFace(
                    face: cart.face(SIMD3(size.width, 0, 0), -ConsoleAxis.front, ConsoleAxis.down, side),
                    camera: camera,
                    shade: 0.35
                ) {
                    LinearGradient(colors: NESInk.cartSide, startPoint: .leading, endPoint: .trailing)
                }
            }
            .opacity(edges)
            ProjectedFace(face: cart.face(.zero, ConsoleAxis.right, ConsoleAxis.down, size), camera: camera) {
                GameMedia(title: title, system: .nes, art: art)
            }
        }
    }
}

struct NESFrontFace: View {
    let power: Double
    let led: Double

    var body: some View {
        Canvas { context, size in
            let unit = size.width / NESShape.width
            let glow = context
            context.scaleBy(x: unit, y: size.height / NESShape.height)
            let sketch = ConsoleSketch(context: context, ink: NESInk.lettering)
            var upper = Path(CGRect(x: 0, y: 0, width: NESShape.width, height: NESShape.split))
            upper.addRect(CGRect(x: NESShape.doorLeft, y: 0, width: NESShape.doorWidth, height: NESShape.split))
            sketch.fill(upper, top: NESInk.shellLit, bottom: NESInk.shellShade, eoFill: true)
            let lower = CGRect(x: 0, y: NESShape.split, width: NESShape.width, height: NESShape.height - NESShape.split)
            sketch.fill(Path(lower), top: NESInk.base, bottom: NESInk.baseShade)
            sketch.rect(0, NESShape.split, NESShape.width, 1, .black.opacity(0.42))
            let panel = Path(roundedRect: NESShape.panel, cornerRadius: 1.4)
            context.fill(panel, with: .color(.black.opacity(0.1)))
            context.stroke(panel, with: .color(.black.opacity(0.32)), lineWidth: 0.5)
            let rim = NESShape.panel
            sketch.rect(rim.minX + 1, rim.maxY - 0.2, rim.width - 2, 0.5, .white.opacity(0.2))
            ConsoleLED(
                rect: NESShape.led,
                off: NESInk.ledOff,
                shine: NESInk.ledShine.opacity(0.8),
                color: GameSystem.nes.powerLED
            )
            .draw(led, in: context, glow: glow, unit: unit)
            button(sketch, NESShape.power.offsetBy(dx: 0, dy: power), word: "POWER")
            button(sketch, NESShape.reset, word: "RESET")
            band(sketch)
            for (index, x) in NESShape.ports.enumerated() {
                port(sketch, x: x, number: index + 1)
            }
            sketch.rect(0, 0, NESShape.doorLeft, 0.6, .white.opacity(0.55))
            sketch.rect(NESShape.doorRight, 0, NESShape.width - NESShape.doorRight, 0.6, .white.opacity(0.55))
            sketch.rect(NESShape.bandLeft, 0, NESShape.bandRight - NESShape.bandLeft, 0.5, .white.opacity(0.22))
        }
    }

    private func button(_ sketch: ConsoleSketch, _ rect: CGRect, word: String) {
        let key = Path(roundedRect: rect, cornerRadius: 0.8)
        sketch.fill(key, top: NESInk.button, bottom: NESInk.buttonShade)
        sketch.context.stroke(key, with: .color(.black.opacity(0.5)), lineWidth: 0.4)
        sketch.rect(rect.minX + 0.5, rect.minY + 0.4, rect.width - 1, 0.6, .white.opacity(0.4))
        sketch.word(word, size: 3.5, tracking: 0.3, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func band(_ sketch: ConsoleSketch) {
        let left = NESShape.bandLeft
        let width = NESShape.bandRight - left
        sketch.fill(
            Path(CGRect(x: left, y: 0, width: width, height: NESShape.height)),
            top: NESInk.band,
            bottom: NESInk.bandShade
        )
        sketch.rect(left, NESShape.split - 0.4, width, 0.8, .black)
        sketch.rect(left, NESShape.split + 0.4, width, 0.4, .white.opacity(0.12))
        sketch.rect(left, 0, 0.5, NESShape.height, .white.opacity(0.1))
        sketch.rect(NESShape.bandRight - 0.5, 0, 0.5, NESShape.height, .black.opacity(0.5))
    }

    private func port(_ sketch: ConsoleSketch, x: Double, number: Int) {
        let socket = NESShape.port.offsetBy(dx: x, dy: 0)
        sketch.word("\(number)", size: 4.2, tracking: 0, at: CGPoint(x: socket.midX, y: socket.minY - 3.7))
        sketch.context.fill(Path(roundedRect: socket, cornerRadius: 1.6), with: .color(NESInk.port))
        var face = Path()
        face.move(to: CGPoint(x: x + 2, y: socket.minY + 5.5))
        face.addArc(
            center: CGPoint(x: x + 5.5, y: socket.minY + 5.5),
            radius: 3.5,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        face.addLine(to: CGPoint(x: x + 9, y: socket.maxY - 2.5))
        face.addLine(to: CGPoint(x: x + 2, y: socket.maxY - 2.5))
        face.closeSubpath()
        sketch.context.fill(face, with: .color(NESInk.portFace))
        let pins = [(4.2, 61.0), (4.2, 64.6), (4.2, 68.2), (4.2, 71.8), (6.8, 62.8), (6.8, 66.4), (6.8, 70.0)]
        for (dx, y) in pins {
            sketch.context.fill(
                Path(ellipseIn: CGRect(x: x + dx - 0.75, y: y - 0.75, width: 1.5, height: 1.5)),
                with: .color(NESInk.pin)
            )
        }
    }
}

struct NESTopFace: View {
    var body: some View {
        Canvas { context, size in
            let depth = NESShape.depth
            context.scaleBy(x: size.width / NESShape.width, y: size.height / depth)
            let sketch = ConsoleSketch(context: context, ink: NESInk.lettering)
            var shell = Path(CGRect(x: 0, y: 0, width: NESShape.width, height: depth))
            shell.addRect(CGRect(
                x: NESShape.doorLeft,
                y: depth - NESShape.strip,
                width: NESShape.doorWidth,
                height: NESShape.strip
            ))
            sketch.fill(shell, top: NESInk.shell, bottom: NESInk.shellLit, eoFill: true)
            let left = NESShape.bandLeft
            let width = NESShape.bandRight - left
            sketch.fill(
                Path(CGRect(x: left, y: 0, width: width, height: depth)),
                top: NESInk.bandShade,
                bottom: NESInk.band
            )
            sketch.rect(left, NESShape.ridgeTop, width, NESShape.ridgeBottom - NESShape.ridgeTop, NESInk.ridge)
            for index in 0..<20 {
                sketch.rect(left, NESShape.ridgeTop + 3 + Double(index) * 6, width, 1.1, NESInk.groove)
            }
            sketch.rect(left, 27, width, 0.8, .black)
            sketch.rect(left, depth - 14, width, 0.8, .black)
            sketch.rect(left - 0.4, 0, 0.4, depth, .black.opacity(0.35))
            sketch.rect(NESShape.bandRight, 0, 0.4, depth, .black.opacity(0.25))
            sketch.rect(NESShape.doorLeft, depth - NESShape.strip - 0.6, NESShape.doorWidth, 0.6, .black.opacity(0.35))
            sketch.rect(0, depth - 0.7, NESShape.doorLeft, 0.7, .white.opacity(0.6))
            sketch.rect(NESShape.doorRight, depth - 0.7, NESShape.width - NESShape.doorRight, 0.7, .white.opacity(0.6))
        }
    }
}

struct NESDoorStrip: View {
    var body: some View {
        Canvas { context, size in
            let width = NESShape.doorWidth
            let strip = NESShape.strip
            context.scaleBy(x: size.width / width, y: size.height / strip)
            let sketch = ConsoleSketch(context: context, ink: NESInk.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: strip)),
                top: NESInk.shell,
                bottom: NESInk.shellLit
            )
            sketch.rect(0, 0, width, 0.8, .black.opacity(0.3))
            sketch.rect(0, strip - 0.7, width, 0.7, .white.opacity(0.6))
            sketch.rect(0, 0, 0.5, strip, .black.opacity(0.25))
            sketch.rect(width - 0.5, 0, 0.5, strip, .black.opacity(0.25))
        }
    }
}

struct NESDoorFront: View {
    var body: some View {
        Canvas { context, size in
            let width = NESShape.doorWidth
            let height = NESShape.split
            context.scaleBy(x: size.width / width, y: size.height / height)
            let sketch = ConsoleSketch(context: context, ink: NESInk.lettering)
            sketch.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                top: NESInk.shellLit,
                bottom: NESInk.shellShade
            )
            sketch.rect(0, 3.2, width, 0.5, .black.opacity(0.18))
            sketch.rect(0, 3.7, width, 0.4, .white.opacity(0.3))
            context.fill(
                Path(roundedRect: CGRect(x: width / 2 + 4, y: height - 2, width: 12, height: 2), cornerRadius: 0.6),
                with: .color(.white.opacity(0.55))
            )
            sketch.rect(0, 0, 0.5, height, .black.opacity(0.3))
            sketch.rect(width - 0.5, 0, 0.5, height, .black.opacity(0.3))
            sketch.rect(0, height - 0.6, width, 0.6, .black.opacity(0.4))
        }
    }
}
