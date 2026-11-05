import SwiftUI

enum SNESShape {
    static let width = 200.0
    static let depth = 242.0
    static let height = 72.0
    static let deckDepth = 112.0
    static let step = 18.0
    static let led = CGRect(x: 28, y: 97.2, width: 4, height: 2.2)
    static let switches = [36.0, 136.0]
    static let ports = [70.0, 104.0]

    static var rearDepth: Double {
        depth - deckDepth
    }
}

extension TopLoader {
    static let snes = TopLoader(
        system: .snes,
        width: SNESShape.width,
        depth: SNESShape.depth,
        height: SNESShape.height,
        slot: Slot(left: 30, right: 170, back: -174, front: -150, top: 0, pit: 34, flap: SNESInk.flap),
        cart: Cart(
            width: 136,
            height: 88,
            thickness: 20,
            sink: 54,
            sideTop: 2,
            end: 22...114,
            endTop: 0,
            shell: SNESInk.cart,
            shade: SNESInk.cartShade
        ),
        powerPeak: -23,
        powerRest: -22,
        led: [
            SIMD3(SNESShape.led.minX, SNESShape.step, SNESShape.led.minY - SNESShape.deckDepth),
            SIMD3(SNESShape.led.maxX, SNESShape.step, SNESShape.led.minY - SNESShape.deckDepth),
            SIMD3(SNESShape.led.minX, SNESShape.step, SNESShape.led.maxY - SNESShape.deckDepth),
            SIMD3(SNESShape.led.maxX, SNESShape.step, SNESShape.led.maxY - SNESShape.deckDepth),
        ]
    )
}

struct SNESConsoleShell: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let power: Double
    let led: Double

    var body: some View {
        let mm = ConsoleStage.unit
        ZStack(alignment: .topLeading) {
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, 0, -SNESShape.depth * mm),
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(SNESShape.width, SNESShape.rearDepth)
                ),
                camera: camera,
                shade: 0.02
            ) {
                SNESRearTop()
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, 0, -SNESShape.deckDepth * mm),
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(SNESShape.width, SNESShape.step)
                ),
                camera: camera,
                shade: 0.1
            ) {
                SNESStep()
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, SNESShape.step, -SNESShape.deckDepth) * mm,
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(SNESShape.width, SNESShape.deckDepth)
                ),
                camera: camera,
                shade: 0.02
            ) {
                SNESDeck(power: power, led: led)
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, SNESShape.step * mm, 0),
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(SNESShape.width, SNESShape.height - SNESShape.step)
                ),
                camera: camera,
                shade: 0.1
            ) {
                SNESFront()
            }
        }
    }
}
