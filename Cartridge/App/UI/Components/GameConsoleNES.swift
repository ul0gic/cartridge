import simd
import SwiftUI

enum NESStage {
    static let doorOpen = 72.0
    static let seam = 1.5
    static let lip = 3.0
}

enum NESShape {
    static let width = 256.0
    static let depth = 203.2
    static let height = 88.9
    static let split = 40.0
    static let doorLeft = 22.0
    static let doorRight = 158.0
    static let strip = 32.0
    static let bandLeft = 158.0
    static let bandRight = 190.0
    static let ridgeTop = 53.2
    static let ridgeBottom = 175.2
    static let cavityFloor = 47.0
    static let cavityDepth = 150.0
    static let panel = CGRect(x: 6, y: 45, width: 90, height: 35)
    static let led = CGRect(x: 11, y: 55.6, width: 4, height: 2.2)
    static let power = CGRect(x: 19, y: 51, width: 27, height: 12)
    static let reset = CGRect(x: 51, y: 51, width: 27, height: 12)
    static let ports = [161.5, 175.5]
    static let port = CGRect(x: 0, y: 54.5, width: 11, height: 25)

    static var doorWidth: Double {
        doorRight - doorLeft
    }
}

enum NESCart {
    static let width = 120.0
    static let height = 133.0
    static let thickness = 19.0
    static let sideLength = 108.0
    static let lieX = -38.0
    static let lieTop = 16.0
    static let push = 10.0
    static let approach = 8.0
    static let seat = -6.0
    static let lift = 60.0
    static let forward = 90.0
}

struct NESCartPose: InsertPose {
    var offset: SIMD3<Double>
    var turn: Double
    var scale: Double

    func mixed(with other: NESCartPose, by amount: Double) -> NESCartPose {
        NESCartPose(
            offset: offset + (other.offset - offset) * amount,
            turn: turn + (other.turn - turn) * amount,
            scale: scale + (other.scale - scale) * amount
        )
    }
}

struct NESInsertFrame {
    let time: Double
    let lift: Double
    let pitch: Double
    let door: Double
    let doorShade: Double
    let power: Double
    let led: Double
    let edges: Double
    let jolt: Double

    private static let doorRise = 660.0
    private static let flipApex = 740.0
    private static let flipEnd = 980.0
    private static let shut = InsertBeat(start: 1330, end: 1410, curve: Motion.insertShut)
    private static let doorShadeKeys = [
        InsertKey(660, 0.1, Motion.insertOut),
        InsertKey(860, 0, .linear),
        InsertKey(1330, 0, Motion.insertShut),
        InsertKey(1410, 0.1, .linear),
    ]
    private static let powerKeys = [
        InsertKey(1420, 0, Motion.insertOut),
        InsertKey(1450, 0.9, Motion.insertOut),
        InsertKey(1500, 0.6, .linear),
    ]
    private static let joltKeys = [
        InsertKey(1330, 0, Motion.insertOut),
        InsertKey(1350, 3, Motion.insertOut),
        InsertKey(1400, 0, .linear),
        InsertKey(1410, 0, Motion.insertOut),
        InsertKey(1425, 1.5, Motion.insertOut),
        InsertKey(1450, 0, .linear),
    ]

    init(time: Double) {
        self.time = time
        lift = ConsoleStage.lift(at: time)
        pitch = ConsoleStage.pitch(at: time)
        let opened = time < Self.doorRise
            ? 0
            : Motion.insertDoor.value(target: 1.0, time: (time - Self.doorRise) / 1000)
        door = NESStage.doorOpen * (time < Self.shut.start ? opened : 1 - Self.shut.progress(time))
        doorShade = InsertFrame.track(time, Self.doorShadeKeys)
        power = InsertFrame.track(time, Self.powerKeys)
        led = ConsoleBeat.led.progress(time)
        edges = ConsoleBeat.edges.progress(time)
        jolt = InsertFrame.track(time, Self.joltKeys)
    }

    var cartInBox: Bool {
        time < ConsoleBeat.handoff
    }

    var cartPassesDoor: Bool {
        time >= ConsoleBeat.slide.start
    }

    func cart(from handoff: NESCartPose) -> NESCartPose {
        let mm = ConsoleStage.unit
        let half = NESCart.height * mm / 2
        let lieY = ConsoleStage.pivotY + NESCart.lieTop * mm - ConsoleStage.mid.y
        let outside = NESCart.approach * mm + half
        let inside = NESCart.seat * mm - half
        let flat = NESCartPose(offset: [NESCart.lieX * mm, lieY, outside], turn: 180, scale: 1)
        let seated = NESCartPose(offset: [NESCart.lieX * mm, lieY, inside], turn: 180, scale: 1)
        let keys = [
            PoseKey(time: ConsoleBeat.handoff, pose: handoff, curve: Motion.insertOut),
            PoseKey(
                time: Self.flipApex,
                pose: NESCartPose(
                    offset: [NESCart.lieX * mm / 2, lieY - NESCart.lift * mm, outside + NESCart.forward * mm],
                    turn: 110,
                    scale: 1
                ),
                curve: Motion.insertInOut
            ),
            PoseKey(time: Self.flipEnd, pose: flat, curve: .linear),
            PoseKey(time: ConsoleBeat.slide.start, pose: flat, curve: ConsoleBeat.slide.curve),
            PoseKey(time: ConsoleBeat.slide.end, pose: seated, curve: .linear),
            PoseKey(time: ConsoleBeat.lock.start, pose: seated, curve: ConsoleBeat.lock.curve),
            PoseKey(
                time: ConsoleBeat.lock.end,
                pose: NESCartPose(offset: seated.offset + [0, NESCart.push * mm, 0], turn: 180, scale: 1),
                curve: .linear
            ),
        ]
        return PoseKey.pose(at: time, keys)
    }

    func ledLens(_ geometry: InsertGeometry) -> CGRect {
        let camera = ConsoleCamera(geometry: geometry, pitch: pitch)
        let rig = ConsoleRig(width: NESShape.width, lift: lift)
        let led = NESShape.led
        return camera.bounds([
            rig.point(SIMD3(led.minX, led.minY, 0)),
            rig.point(SIMD3(led.maxX, led.minY, 0)),
            rig.point(SIMD3(led.minX, led.maxY, 0)),
            rig.point(SIMD3(led.maxX, led.maxY, 0)),
        ])
    }

    func flashCenter(_ geometry: InsertGeometry) -> CGPoint {
        ConsoleCamera(geometry: geometry).app(
            x: ConsoleStage.mid.x + NESCart.lieX * ConsoleStage.unit,
            y: ConsoleStage.pivotY + 14 * ConsoleStage.unit
        )
    }
}

struct NESCartRig {
    let pose: NESCartPose

    func face(_ origin: SIMD3<Double>, _ across: SIMD3<Double>, _ down: SIMD3<Double>, _ size: CGSize) -> ConsoleFace {
        let turn = simd_quatd(angle: pose.turn * .pi / 180, axis: normalize(SIMD3(0, -1, 1)))
        let center = SIMD3(ConsoleStage.mid.x, ConsoleStage.mid.y, 0) + pose.offset
        let half = SIMD3(NESCart.width, NESCart.height, 0) * ConsoleStage.unit / 2
        return ConsoleFace(
            origin: center + turn.act((origin - half) * pose.scale),
            across: turn.act(across) * pose.scale,
            down: turn.act(down) * pose.scale,
            size: size
        )
    }
}

struct NESConsoleScene: View {
    let title: String
    let art: TileArt
    let frame: NESInsertFrame
    let geometry: InsertGeometry

    var body: some View {
        let camera = ConsoleCamera(geometry: geometry, pitch: frame.pitch)
        let rig = ConsoleRig(width: NESShape.width, lift: frame.lift)
        let cart = frame.cartInBox ? nil : NESCartRig(pose: frame.cart(from: handoff))
        ZStack(alignment: .topLeading) {
            NESConsoleUnder(rig: rig, camera: camera)
            if let cart, frame.cartPassesDoor {
                cartFaces(cart, camera)
            }
            NESConsoleShell(rig: rig, camera: camera, power: frame.power, led: frame.led)
            NESConsoleDoor(rig: rig, camera: camera, door: frame.door, shade: frame.doorShade)
            if let cart, !frame.cartPassesDoor {
                cartFaces(cart, camera)
            } else if let cart, cart.pose.offset.z + NESCart.height * ConsoleStage.unit / 2 > 0 {
                let doorLine = camera.screen(SIMD3(
                    cart.pose.offset.x + ConsoleStage.mid.x,
                    cart.pose.offset.y + ConsoleStage.mid.y,
                    0
                )).y
                cartFaces(cart, camera)
                    .mask {
                        Rectangle().offset(y: doorLine)
                    }
            }
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
        .offset(y: frame.jolt * camera.scale)
    }

    private var handoff: NESCartPose {
        let start = geometry.handoff(width: NESCart.width)
        return NESCartPose(offset: start.offset, turn: 0, scale: start.scale)
    }

    private func cartFaces(_ cart: NESCartRig, _ camera: ConsoleCamera) -> some View {
        NESCartFaces(cart: cart, camera: camera, edges: frame.edges, title: title, art: art)
            .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
    }
}
