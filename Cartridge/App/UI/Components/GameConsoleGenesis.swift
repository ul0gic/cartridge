import SwiftUI

enum GenesisShape {
    static let width = 280.0
    static let depth = 210.0
    static let height = 70.0
    static let deck = 10.0
    static let chamferRun = 20.0
    static let chamferDrop = 28.0
    static let ringRadius = 70.0
    static let ringCenter = SIMD2(190.0, -112.0)
    static let led = CGRect(x: 67, y: 117.4, width: 4, height: 2.2)

    static var deckDepth: Double {
        depth - chamferRun
    }

    static var frontHeight: Double {
        height - chamferDrop
    }

    static var ringOrigin: SIMD2<Double> {
        ringCenter - SIMD2(ringRadius, ringRadius)
    }

    static var ledCorners: [SIMD3<Double>] {
        let origin = ringOrigin
        return [led.minY, led.maxY].flatMap { row in
            [led.minX, led.maxX].map { x in SIMD3(origin.x + x, 0, origin.y + row) }
        }
    }
}

extension TopLoader {
    static let genesis = TopLoader(
        system: .genesis,
        width: GenesisShape.width,
        depth: GenesisShape.depth,
        height: GenesisShape.height,
        slot: Slot(left: 134, right: 246, back: -150, front: -128, top: 0, pit: 34, flap: GenesisInk.flap),
        cart: Cart(
            width: 108,
            height: 70.3,
            thickness: 19,
            sink: 30,
            sideTop: 0,
            end: 0...108,
            endTop: 0,
            shell: GenesisInk.cart,
            shade: GenesisInk.cartShade
        ),
        powerPeak: -19,
        powerRest: -18,
        led: GenesisShape.ledCorners
    )
}

struct GenesisConsoleShell: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let power: Double
    let led: Double

    var body: some View {
        let mm = ConsoleStage.unit
        let rise = GenesisShape.chamferDrop - GenesisShape.deck
        let slant = (rise * rise + GenesisShape.chamferRun * GenesisShape.chamferRun).squareRoot()
        ZStack(alignment: .topLeading) {
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, GenesisShape.deck, -GenesisShape.depth) * mm,
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(GenesisShape.width, GenesisShape.deckDepth)
                ),
                camera: camera,
                shade: 0.02
            ) {
                GenesisDeck(power: power)
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(GenesisShape.ringOrigin.x, 0, GenesisShape.ringOrigin.y) * mm,
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(2 * GenesisShape.ringRadius, 2 * GenesisShape.ringRadius)
                ),
                camera: camera
            ) {
                GenesisRing(led: led)
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, GenesisShape.deck, -GenesisShape.chamferRun) * mm,
                    ConsoleAxis.right,
                    SIMD3(0, rise, GenesisShape.chamferRun) / slant,
                    ConsoleStage.size(GenesisShape.width, slant)
                ),
                camera: camera,
                shade: 0.04
            ) {
                GenesisChamfer(length: slant)
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, GenesisShape.chamferDrop * mm, 0),
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(GenesisShape.width, GenesisShape.frontHeight)
                ),
                camera: camera,
                shade: 0.1
            ) {
                GenesisFront()
            }
        }
    }
}
