import simd
import SwiftUI

struct TopLoader {
    enum Layer {
        case underShell
        case overShell
    }

    struct Slot {
        let left: Double
        let right: Double
        let back: Double
        let front: Double
        let top: Double
        let pit: Double
        let flap: Color
        var layer = Layer.underShell
    }

    struct Cart {
        let width: Double
        let height: Double
        let thickness: Double
        let sink: Double
        let sideTop: Double
        let end: ClosedRange<Double>?
        let endTop: Double
        let shell: Color
        let shade: Color
    }

    let system: GameSystem
    let width: Double
    let depth: Double
    let height: Double
    let slot: Slot
    let cart: Cart
    let powerPeak: Double
    let powerRest: Double
    let led: [SIMD3<Double>]
}

struct TopLoaderFrame {
    let console: TopLoader
    let time: Double
    let lift: Double
    let pitch: Double
    let power: Double
    let led: Double
    let edges: Double
    let jolt: Double
    let cast: Double
    let flap: Double

    static let flapOpen = 88.0
    private static let apex = 740.0
    private static let hover = 26.0
    private static let push = 8.0
    private static let gap = 1.5
    private static let apexLift = 40.0
    private static let apexForward = 30.0
    private static let apexYaw = -18.0
    private static let apexTilt = 14.0
    private static let flapSpan = 90.0
    private static let castKeys = [
        InsertKey(apex, 0, Motion.insertOut),
        InsertKey(ConsoleBeat.slide.start, 0.6, ConsoleBeat.slide.curve),
        InsertKey(ConsoleBeat.slide.end, 0.85, .linear),
    ]
    private static let joltKeys = [
        InsertKey(ConsoleBeat.lock.end, 0, Motion.insertOut),
        InsertKey(1350, 3, Motion.insertOut),
        InsertKey(1400, 0, .linear),
    ]

    init(time: Double, console: TopLoader) {
        self.console = console
        self.time = time
        lift = ConsoleStage.lift(at: time)
        pitch = ConsoleStage.pitch(at: time)
        power = InsertFrame.track(time, [
            InsertKey(1420, 0, Motion.insertOut),
            InsertKey(1460, console.powerPeak, Motion.insertOut),
            InsertKey(1500, console.powerRest, .linear),
        ])
        led = ConsoleBeat.led.progress(time)
        edges = ConsoleBeat.edges.progress(time)
        jolt = InsertFrame.track(time, Self.joltKeys)
        cast = InsertFrame.track(time, Self.castKeys)
        let slide = ConsoleBeat.slide
        let reach = Self.hover / (Self.hover + console.cart.sink - Self.push)
        let contact = slide.start + (slide.end - slide.start) * slide.curve.inverse.value(at: reach)
        flap = InsertBeat(start: contact, end: contact + Self.flapSpan, curve: Motion.insertOut).progress(time)
    }

    var cartInBox: Bool {
        time < ConsoleBeat.handoff
    }

    var cartInSlot: Bool {
        time >= ConsoleBeat.slide.start
    }

    var slotEdge: SIMD3<Double> {
        let slot = console.slot
        return SIMD3((slot.left + slot.right) / 2, slot.top, slot.front)
    }

    func cart(from handoff: CartPose) -> CartPose {
        let mm = ConsoleStage.unit
        let slot = console.slot
        let x = ((slot.left + slot.right) / 2 - console.width / 2) * mm
        let depth = (slot.front - Self.gap) * mm
        let bottom = { (y: Double) in
            ConsoleStage.pivotY + y * mm - ConsoleStage.mid.y - console.cart.height * mm / 2
        }
        let upright = { (y: Double) in CartPose(offset: [x, bottom(y), depth], yaw: 0, tilt: 0, scale: 1) }
        let hover = upright(slot.top - Self.hover)
        let pushed = upright(slot.top + console.cart.sink - Self.push)
        let apex = CartPose(
            offset: [x / 2, hover.offset.y - Self.apexLift * mm, depth / 2 + Self.apexForward * mm],
            yaw: Self.apexYaw,
            tilt: Self.apexTilt,
            scale: 1
        )
        return PoseKey.pose(at: time, [
            PoseKey(time: ConsoleBeat.handoff, pose: handoff, curve: Motion.insertOut),
            PoseKey(time: Self.apex, pose: apex, curve: Motion.insertInOut),
            PoseKey(time: ConsoleBeat.slide.start, pose: hover, curve: ConsoleBeat.slide.curve),
            PoseKey(time: ConsoleBeat.slide.end, pose: pushed, curve: .linear),
            PoseKey(time: ConsoleBeat.lock.start, pose: pushed, curve: ConsoleBeat.lock.curve),
            PoseKey(time: ConsoleBeat.lock.end, pose: upright(slot.top + console.cart.sink), curve: .linear),
        ])
    }

    func ledLens(_ geometry: InsertGeometry) -> CGRect {
        let camera = ConsoleCamera(geometry: geometry, pitch: pitch)
        let rig = ConsoleRig(width: console.width, lift: lift)
        return camera.bounds(console.led.map(rig.point))
    }

    func flashCenter(_ geometry: InsertGeometry) -> CGPoint {
        let camera = ConsoleCamera(geometry: geometry, pitch: ConsoleStage.pitch)
        return camera.screen(ConsoleRig(width: console.width, lift: 0).point(slotEdge))
    }
}

struct CartPose: InsertPose {
    var offset: SIMD3<Double>
    var yaw: Double
    var tilt: Double
    var scale: Double

    func mixed(with other: CartPose, by amount: Double) -> CartPose {
        CartPose(
            offset: offset + (other.offset - offset) * amount,
            yaw: yaw + (other.yaw - yaw) * amount,
            tilt: tilt + (other.tilt - tilt) * amount,
            scale: scale + (other.scale - scale) * amount
        )
    }
}

struct CartRig {
    let pose: CartPose
    let cart: TopLoader.Cart

    func face(_ origin: SIMD3<Double>, _ across: SIMD3<Double>, _ down: SIMD3<Double>, _ size: CGSize) -> ConsoleFace {
        let turn = simd_quatd(angle: pose.yaw * .pi / 180, axis: ConsoleAxis.down)
            * simd_quatd(angle: pose.tilt * .pi / 180, axis: ConsoleAxis.right)
        let center = SIMD3(ConsoleStage.mid.x, ConsoleStage.mid.y, 0) + pose.offset
        let half = SIMD3(cart.width, cart.height, 0) * ConsoleStage.unit / 2
        return ConsoleFace(
            origin: center + turn.act((origin - half) * pose.scale),
            across: turn.act(across) * pose.scale,
            down: turn.act(down) * pose.scale,
            size: size
        )
    }
}

struct TopLoaderScene<Shell: View>: View {
    let title: String
    let art: TileArt
    let frame: TopLoaderFrame
    let geometry: InsertGeometry
    @ViewBuilder let shell: (ConsoleRig, ConsoleCamera) -> Shell

    var body: some View {
        let console = frame.console
        let camera = ConsoleCamera(geometry: geometry, pitch: frame.pitch)
        let rig = ConsoleRig(width: console.width, lift: frame.lift)
        ZStack(alignment: .topLeading) {
            ConsoleFloorShadow(rig: rig, camera: camera, depth: console.depth, height: console.height)
            let slot = TopLoaderSlot(slot: console.slot, rig: rig, camera: camera, flap: frame.flap)
            switch console.slot.layer {
            case .underShell:
                slot
                shell(rig, camera)
            case .overShell:
                shell(rig, camera)
                slot
                    .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
                    .mask(alignment: .topLeading) {
                        opening(rig, camera)
                            .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
                    }
            }
            cast(rig, camera)
            if !frame.cartInBox {
                let faces = TopLoaderCartFaces(
                    cart: CartRig(pose: frame.cart(from: handoff), cart: console.cart),
                    camera: camera,
                    system: console.system,
                    edges: frame.edges,
                    title: title,
                    art: art
                )
                .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
                if frame.cartInSlot {
                    let edge = camera.screen(rig.point(frame.slotEdge)).y
                    faces.mask(alignment: .top) {
                        Rectangle().frame(height: max(0, edge))
                    }
                } else {
                    faces
                }
            }
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
        .offset(y: frame.jolt * camera.scale)
    }

    private var handoff: CartPose {
        let start = geometry.handoff(width: frame.console.cart.width)
        return CartPose(offset: start.offset, yaw: 0, tilt: 0, scale: start.scale)
    }

    private func opening(_ rig: ConsoleRig, _ camera: ConsoleCamera) -> some View {
        let slot = frame.console.slot
        return ProjectedFace(
            face: rig.face(
                SIMD3(slot.left, slot.top, slot.back) * ConsoleStage.unit,
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(slot.right - slot.left, slot.front - slot.back)
            ),
            camera: camera
        ) {
            RoundedRectangle(cornerRadius: 1.5 * ConsoleStage.unit * camera.scale)
        }
    }

    private func cast(_ rig: ConsoleRig, _ camera: ConsoleCamera) -> some View {
        let slot = frame.console.slot
        return ProjectedFace(
            face: rig.face(
                SIMD3(slot.left - 16, slot.top - 0.3, slot.back - 30) * ConsoleStage.unit,
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(slot.right - slot.left + 32, slot.front - slot.back + 44)
            ),
            camera: camera
        ) {
            EllipticalGradient(colors: [.black.opacity(0.55), .clear])
        }
        .opacity(frame.cast)
    }
}

struct TopLoaderSlot: View {
    let slot: TopLoader.Slot
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let flap: Double

    private static let pit = MediaInk.gray(0x05, 0x05, 0x06)
    private static let pitLit = MediaInk.gray(0x1D, 0x1D, 0x21)

    var body: some View {
        let mm = ConsoleStage.unit
        let width = slot.right - slot.left
        let half = (slot.front - slot.back) / 2
        let angle = TopLoaderFrame.flapOpen * flap
        ZStack(alignment: .topLeading) {
            ProjectedFace(
                face: rig.face(
                    SIMD3(slot.left - 10, slot.top + slot.pit, slot.back - 10) * mm,
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(width + 20, 2 * half + 20)
                ),
                camera: camera
            ) {
                EllipticalGradient(colors: [Self.pitLit, Self.pit])
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(slot.left, slot.top, slot.back) * mm,
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(width, slot.pit)
                ),
                camera: camera
            ) {
                LinearGradient(colors: [Self.pitLit, Self.pit], startPoint: .top, endPoint: .bottom)
            }
            flapFace(
                rig.hinge(SIMD3(slot.left, slot.top, slot.front), angle)
                    .face(SIMD3(0, 0, -half * mm), ConsoleAxis.right, ConsoleAxis.front, ConsoleStage.size(width, half))
            )
            flapFace(
                rig.hinge(SIMD3(slot.left, slot.top, slot.back), -angle)
                    .face(.zero, ConsoleAxis.right, ConsoleAxis.front, ConsoleStage.size(width, half))
            )
        }
    }

    private func flapFace(_ face: ConsoleFace) -> some View {
        ProjectedFace(face: face, camera: camera, shade: 0.55 * flap, twoSided: true) {
            LinearGradient(
                colors: [slot.flap, slot.flap.mix(with: .black, by: 0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct TopLoaderCartFaces: View {
    let cart: CartRig
    let camera: ConsoleCamera
    let system: GameSystem
    let edges: Double
    let title: String
    let art: TileArt

    var body: some View {
        let mm = ConsoleStage.unit
        let shape = cart.cart
        let thickness = shape.thickness * mm
        let side = CGSize(width: thickness, height: (shape.height - shape.sideTop) * mm)
        let sideShade = [shape.shade, shape.shade.mix(with: .black, by: 0.15)]
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if let end = shape.end {
                    ProjectedFace(
                        face: cart.face(
                            SIMD3(end.lowerBound * mm, shape.endTop * mm, -thickness),
                            ConsoleAxis.right,
                            ConsoleAxis.front,
                            CGSize(width: (end.upperBound - end.lowerBound) * mm, height: thickness)
                        ),
                        camera: camera
                    ) {
                        LinearGradient(
                            colors: [shape.shell.mix(with: .black, by: 0.12), shape.shell],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                ProjectedFace(
                    face: cart.face(
                        SIMD3(0, shape.sideTop * mm, -thickness),
                        ConsoleAxis.front,
                        ConsoleAxis.down,
                        side
                    ),
                    camera: camera,
                    shade: 0.35
                ) {
                    LinearGradient(colors: sideShade, startPoint: .leading, endPoint: .trailing)
                }
                ProjectedFace(
                    face: cart.face(
                        SIMD3(shape.width * mm, shape.sideTop * mm, 0),
                        -ConsoleAxis.front,
                        ConsoleAxis.down,
                        side
                    ),
                    camera: camera,
                    shade: 0.35
                ) {
                    LinearGradient(colors: sideShade, startPoint: .leading, endPoint: .trailing)
                }
            }
            .opacity(edges)
            ProjectedFace(
                face: cart.face(
                    .zero,
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(shape.width, shape.height)
                ),
                camera: camera
            ) {
                GameMedia(title: title, system: system, art: art)
            }
        }
    }
}
