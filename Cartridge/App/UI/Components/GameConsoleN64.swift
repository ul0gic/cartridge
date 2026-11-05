import SwiftUI

enum N64Shape {
    static let width = 260.0
    static let depth = 190.0
    static let height = 73.0
    static let corner = 30.0
    static let hump = CGRect(x: 64, y: -152, width: 132, height: 62)
    static let humpHeight = 7.0
    static let lobeWidth = 40.0
    static let lobeTop = 36.0
    static let lobeReach = 14.0
    static let lobeBevel = 18.0
    static let led = CGRect(x: 62, y: 160, width: 4, height: 2.2)
    static let switches = [30.0, 202.0]
    static let ports = [28.0, 60.0, 140.0, 172.0]
    static let leftBevel = SIMD3<Double>(1, 0, 1) / 2.0.squareRoot()
    static let rightBevel = SIMD3<Double>(1, 0, -1) / 2.0.squareRoot()

    static var frontWidth: Double {
        width - 2 * corner
    }

    static var lobeHeight: Double {
        height - lobeTop
    }
}

extension TopLoader {
    static let n64 = TopLoader(
        system: .n64,
        width: N64Shape.width,
        depth: N64Shape.depth,
        height: N64Shape.height,
        slot: Slot(
            left: 70,
            right: 190,
            back: -130,
            front: -110,
            top: -N64Shape.humpHeight,
            pit: 40,
            flap: N64Ink.flap,
            layer: .overShell
        ),
        cart: Cart(
            width: 116,
            height: 76,
            thickness: 18,
            sink: 40,
            sideTop: 12.6,
            end: nil,
            endTop: 1,
            shell: N64Ink.cart,
            shade: N64Ink.cartShade
        ),
        powerPeak: 19,
        powerRest: 18,
        led: [
            SIMD3(N64Shape.led.minX, 0, N64Shape.led.minY - N64Shape.depth),
            SIMD3(N64Shape.led.maxX, 0, N64Shape.led.minY - N64Shape.depth),
            SIMD3(N64Shape.led.minX, 0, N64Shape.led.maxY - N64Shape.depth),
            SIMD3(N64Shape.led.maxX, 0, N64Shape.led.maxY - N64Shape.depth),
        ]
    )
}

struct N64ConsoleShell: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let power: Double
    let led: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            chassis
            lobes
        }
    }

    private var chassis: some View {
        let hump = N64Shape.hump
        let corner = N64Shape.corner
        return ZStack(alignment: .topLeading) {
            panel(
                SIMD3(0, 0, -N64Shape.depth),
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(N64Shape.width, N64Shape.depth)
            ) {
                N64Top(power: power, led: led)
            }
            panel(
                SIMD3(hump.minX, -N64Shape.humpHeight, hump.minY),
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(hump.width, hump.height)
            ) {
                N64HumpTop()
            }
            panel(
                SIMD3(hump.minX + 10, -N64Shape.humpHeight, hump.maxY),
                ConsoleAxis.right,
                ConsoleAxis.down,
                ConsoleStage.size(hump.width - 20, N64Shape.humpHeight),
                shade: 0.1
            ) {
                N64Slab(kind: .hump)
            }
            panel(
                SIMD3(corner, 0, 0),
                ConsoleAxis.right,
                ConsoleAxis.down,
                ConsoleStage.size(N64Shape.frontWidth, N64Shape.height),
                shade: 0.1
            ) {
                N64Front()
            }
            panel(
                SIMD3(0, 0, -corner),
                N64Shape.leftBevel,
                ConsoleAxis.down,
                ConsoleStage.size(corner * 2.0.squareRoot(), N64Shape.height),
                shade: 0.12
            ) {
                N64Slab(kind: .corner)
            }
            panel(
                SIMD3(N64Shape.width - corner, 0, 0),
                N64Shape.rightBevel,
                ConsoleAxis.down,
                ConsoleStage.size(corner * 2.0.squareRoot(), N64Shape.height),
                shade: 0.18
            ) {
                N64Slab(kind: .corner)
            }
        }
    }

    private var lobes: some View {
        let top = N64Shape.lobeTop
        let reach = N64Shape.lobeReach
        let bevel = N64Shape.lobeBevel
        let flat = N64Shape.lobeWidth - bevel
        let face = bevel * 2.0.squareRoot()
        let right = N64Shape.width - N64Shape.lobeWidth
        return ZStack(alignment: .topLeading) {
            panel(
                SIMD3(0, top, -N64Shape.corner),
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(N64Shape.lobeWidth, reach + N64Shape.corner)
            ) {
                N64LobeTop(left: true)
            }
            panel(
                SIMD3(right, top, -N64Shape.corner),
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(N64Shape.lobeWidth, reach + N64Shape.corner)
            ) {
                N64LobeTop(left: false)
            }
            panel(
                SIMD3(bevel, top, reach),
                ConsoleAxis.right,
                ConsoleAxis.down,
                ConsoleStage.size(flat, N64Shape.lobeHeight),
                shade: 0.1
            ) {
                N64Slab(kind: .lobe)
            }
            panel(
                SIMD3(right, top, reach),
                ConsoleAxis.right,
                ConsoleAxis.down,
                ConsoleStage.size(flat, N64Shape.lobeHeight),
                shade: 0.1
            ) {
                N64Slab(kind: .lobe)
            }
            panel(
                SIMD3(0, top, reach - bevel),
                N64Shape.leftBevel,
                ConsoleAxis.down,
                ConsoleStage.size(face, N64Shape.lobeHeight),
                shade: 0.2
            ) {
                N64Slab(kind: .lobe)
            }
            panel(
                SIMD3(N64Shape.width - bevel, top, reach),
                N64Shape.rightBevel,
                ConsoleAxis.down,
                ConsoleStage.size(face, N64Shape.lobeHeight),
                shade: 0.26
            ) {
                N64Slab(kind: .lobe)
            }
            panel(
                SIMD3(N64Shape.lobeWidth, top, reach),
                -ConsoleAxis.front,
                ConsoleAxis.down,
                ConsoleStage.size(reach, N64Shape.lobeHeight),
                shade: 0.3
            ) {
                N64Slab(kind: .lobe)
            }
            panel(
                SIMD3(right, top, 0),
                ConsoleAxis.front,
                ConsoleAxis.down,
                ConsoleStage.size(reach, N64Shape.lobeHeight),
                shade: 0.3
            ) {
                N64Slab(kind: .lobe)
            }
        }
    }

    private func panel(
        _ origin: SIMD3<Double>,
        _ across: SIMD3<Double>,
        _ down: SIMD3<Double>,
        _ size: CGSize,
        shade: Double = 0,
        @ViewBuilder content: () -> some View
    ) -> some View {
        ProjectedFace(
            face: rig.face(origin * ConsoleStage.unit, across, down, size),
            camera: camera,
            shade: shade
        ) {
            content()
        }
    }
}
