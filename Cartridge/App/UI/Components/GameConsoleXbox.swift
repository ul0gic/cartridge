import SwiftUI

enum XboxShape {
    static let width = 320.0
    static let height = 91.0
    static let depth = 259.0
    static let tray = CGRect(x: 6, y: 8, width: 118, height: 16)
    static let trayTravel = 150.0
    static let discRest = 7.5
    static let hover = 50.0
    static let power = CGPoint(x: 160.5, y: 71)
    static let ringRadius = 6.5
    static let ringWidth = 1.6
}

enum XboxDisc {
    static let diameter = 120.0
    static let apexRise = 30.0
    static let apexForward = 30.0
    static let apexTilt = 80.0
    static let bounce = 1.2
    static let lidOpen = 118.0
    static let boxLid = InsertBeat(start: 140, end: 440, curve: Motion.insertPull)
    static let boxLift = InsertBeat(start: 260, end: 480, curve: Motion.insertOut)

    static func boxBeats(in console: ConsoleInsertFrame?) -> (lid: InsertBeat, lift: InsertBeat) {
        guard case .xbox? = console else { return PS1Disc.boxBeats(in: console) }
        return (boxLid, boxLift)
    }
}

struct XboxInsertFrame {
    static let settled = 1000.0

    let time: Double
    let lift: Double
    let pitch: Double
    let tray: Double
    let led: Double

    private static let trayOut = InsertBeat(start: 520, end: 760, curve: Motion.insertSlide)
    private static let apex = 740.0
    private static let hover = 860.0
    private static let seated = 960.0
    private static let bounceTop = 985.0

    init(time: Double) {
        self.time = time
        lift = ConsoleStage.lift(at: time)
        pitch = ConsoleStage.pitch(at: time)
        tray = time < ConsoleBeat.slide.start ? Self.trayOut.progress(time) : 1 - ConsoleBeat.slide.progress(time)
        led = ConsoleBeat.led.progress(time)
    }

    var cartInBox: Bool {
        time < ConsoleBeat.handoff
    }

    func disc(from handoff: PS1DiscPose) -> PS1DiscPose {
        let mm = ConsoleStage.unit
        let x = (XboxShape.tray.midX - XboxShape.width / 2) * mm
        let middle = XboxShape.trayTravel / 2
        let flat = { (y: Double, forward: Double) in
            PS1DiscPose(
                offset: [x, ConsoleStage.pivotY + y * mm - ConsoleStage.mid.y, forward * mm],
                tilt: 90,
                scale: 1
            )
        }
        let rest = XboxShape.discRest
        guard time <= Self.settled else {
            return flat(rest, middle - XboxShape.trayTravel * (1 - tray))
        }
        let hover = flat(rest - XboxShape.hover, middle)
        let seated = flat(rest, middle)
        let apex = PS1DiscPose(
            offset: [
                (handoff.offset.x + x) / 2,
                hover.offset.y - XboxDisc.apexRise * mm,
                (XboxShape.trayTravel / 4 + XboxDisc.apexForward) * mm,
            ],
            tilt: XboxDisc.apexTilt,
            scale: 1
        )
        return PoseKey.pose(at: time, [
            PoseKey(time: ConsoleBeat.handoff, pose: handoff, curve: Motion.insertOut),
            PoseKey(time: Self.apex, pose: apex, curve: Motion.insertInOut),
            PoseKey(time: Self.hover, pose: hover, curve: Motion.insertGravity),
            PoseKey(time: Self.seated, pose: seated, curve: Motion.insertOut),
            PoseKey(time: Self.bounceTop, pose: flat(rest - XboxDisc.bounce, middle), curve: Motion.insertIn),
            PoseKey(time: Self.settled, pose: seated, curve: .linear),
        ])
    }

    func ledLens(_ geometry: InsertGeometry) -> CGRect {
        let camera = ConsoleCamera(geometry: geometry, pitch: pitch)
        let rig = ConsoleRig(width: XboxShape.width, lift: lift)
        let center = XboxShape.power
        let radius = XboxShape.ringRadius
        return camera.bounds([
            rig.point(SIMD3(center.x - radius, center.y - radius, 0)),
            rig.point(SIMD3(center.x + radius, center.y - radius, 0)),
            rig.point(SIMD3(center.x - radius, center.y + radius, 0)),
            rig.point(SIMD3(center.x + radius, center.y + radius, 0)),
        ])
    }

    func flashCenter(_ geometry: InsertGeometry) -> CGPoint {
        let camera = ConsoleCamera(geometry: geometry, pitch: ConsoleStage.pitch)
        let slot = XboxShape.tray
        return camera.screen(ConsoleRig(width: XboxShape.width, lift: 0).point(SIMD3(slot.midX, slot.minY, 0)))
    }
}

struct XboxConsoleScene: View {
    let title: String
    let art: TileArt
    let frame: XboxInsertFrame
    let geometry: InsertGeometry

    var body: some View {
        let camera = ConsoleCamera(geometry: geometry, pitch: frame.pitch)
        let rig = ConsoleRig(width: XboxShape.width, lift: frame.lift)
        ZStack(alignment: .topLeading) {
            ConsoleFloorShadow(rig: rig, camera: camera, depth: XboxShape.depth, height: XboxShape.height)
            XboxConsoleShell(rig: rig, camera: camera, led: frame.led)
            XboxConsoleTray(rig: rig, camera: camera, out: frame.tray)
            if !frame.cartInBox {
                discFace(frame.disc(from: handoff), camera)
            }
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
    }

    private var handoff: PS1DiscPose {
        let start = geometry.discHandoff
        return PS1DiscPose(offset: start.offset, tilt: 0, scale: start.scale)
    }

    private func discFace(_ pose: PS1DiscPose, _ camera: ConsoleCamera) -> some View {
        let inside = frame.time > XboxInsertFrame.settled
            ? min(1, max(0, 0.5 - pose.offset.z / (XboxDisc.diameter * ConsoleStage.unit)))
            : 0
        return ProjectedFace(face: pose.face, camera: camera) {
            GameMedia(title: title, system: .xbox, art: art)
                .mask(Rectangle().scale(x: 1, y: 1 - inside, anchor: .bottom))
        }
    }
}

struct XboxConsoleShell: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let led: Double

    var body: some View {
        let mm = ConsoleStage.unit
        let side = ConsoleStage.size(XboxShape.depth, XboxShape.height)
        ZStack(alignment: .topLeading) {
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, 0, -XboxShape.depth * mm),
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(XboxShape.width, XboxShape.depth)
                ),
                camera: camera,
                shade: 0.02
            ) {
                XboxTop()
            }
            ProjectedFace(
                face: rig.face(SIMD3(0, 0, -XboxShape.depth * mm), ConsoleAxis.front, ConsoleAxis.down, side),
                camera: camera,
                shade: 0.25
            ) {
                XboxSide()
            }
            ProjectedFace(
                face: rig.face(SIMD3(XboxShape.width * mm, 0, 0), -ConsoleAxis.front, ConsoleAxis.down, side),
                camera: camera,
                shade: 0.25
            ) {
                XboxSide()
            }
            ProjectedFace(
                face: rig.face(
                    .zero,
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(XboxShape.width, XboxShape.height)
                ),
                camera: camera,
                shade: 0.1
            ) {
                XboxFront(led: led)
            }
        }
    }
}

struct XboxConsoleTray: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let out: Double

    var body: some View {
        let mm = ConsoleStage.unit
        let tray = XboxShape.tray
        let reach = out * XboxShape.trayTravel
        let front = reach * mm
        let side = ConsoleStage.size(reach, tray.height)
        ZStack(alignment: .topLeading) {
            if reach > 0 {
                ProjectedFace(
                    face: rig.face(SIMD3(tray.minX * mm, tray.minY * mm, 0), ConsoleAxis.front, ConsoleAxis.down, side),
                    camera: camera,
                    shade: 0.25
                ) {
                    XboxInk.shellShade
                }
                ProjectedFace(
                    face: rig.face(
                        SIMD3(tray.maxX * mm, tray.minY * mm, front),
                        -ConsoleAxis.front,
                        ConsoleAxis.down,
                        side
                    ),
                    camera: camera,
                    shade: 0.25
                ) {
                    XboxInk.shellShade
                }
                ProjectedFace(
                    face: rig.face(
                        SIMD3(tray.minX * mm, tray.minY * mm, 0),
                        ConsoleAxis.right,
                        ConsoleAxis.front,
                        ConsoleStage.size(tray.width, reach)
                    ),
                    camera: camera,
                    shade: 0.02
                ) {
                    XboxTrayTop(out: out)
                }
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(tray.minX * mm, tray.minY * mm, front),
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(tray.width, tray.height)
                ),
                camera: camera,
                shade: 0.1
            ) {
                LinearGradient(colors: [XboxInk.shellLit, XboxInk.shell], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
