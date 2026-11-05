import SwiftUI

enum PS1Shape {
    static let width = 275.0
    static let depth = 190.0
    static let height = 63.0
    static let band = 24.0
    static let lidX = 145.0
    static let lidZ = -98.0
    static let lidRadius = 66.0
    static let lidRaise = 1.2
    static let lidThickness = 0.6
    static let lidOpen = 74.0
    static let hole = 63.0
    static let well = 14.0
    static let rest = 12.0
    static let hover = 50.0
    static let blockLeft = 95.0
    static let blockRight = 180.0
    static let blockTop = 24.0
    static let blockReach = 10.0
    static let led = CGRect(x: 18, y: 168, width: 4, height: 2.2)

    static var blockWidth: Double {
        blockRight - blockLeft
    }

    static var blockHeight: Double {
        height - blockTop
    }
}

enum PS1Disc {
    static let diameter = 120.0
    static let boxRise = 0.3
    static let apexRise = 30.0
    static let apexForward = 30.0
    static let apexTilt = 80.0
    static let bounce = 1.2
    static let spin = 1080.0
    static let boxLid = InsertBeat(start: 140, end: 440, curve: Motion.insertPull)
    static let boxLift = InsertBeat(start: 260, end: 480, curve: Motion.insertOut)

    static func boxBeats(in console: ConsoleInsertFrame?) -> (lid: InsertBeat, lift: InsertBeat) {
        guard case .ps1? = console else { return (InsertBeat.lid, InsertBeat.lift) }
        return (boxLid, boxLift)
    }
}

struct PS1DiscPose: InsertPose {
    var offset: SIMD3<Double>
    var tilt: Double
    var scale: Double

    func mixed(with other: PS1DiscPose, by amount: Double) -> PS1DiscPose {
        PS1DiscPose(
            offset: offset + (other.offset - offset) * amount,
            tilt: tilt + (other.tilt - tilt) * amount,
            scale: scale + (other.scale - scale) * amount
        )
    }

    var face: ConsoleFace {
        let radius = PS1Disc.diameter * ConsoleStage.unit / 2
        let across = ConsoleAxis.right * scale
        let down = ConsoleCamera.rotated(ConsoleAxis.down, degrees: tilt) * scale
        let center = SIMD3(ConsoleStage.mid.x, ConsoleStage.mid.y, 0) + offset
        return ConsoleFace(
            origin: center - (across + down) * radius,
            across: across,
            down: down,
            size: ConsoleStage.size(PS1Disc.diameter, PS1Disc.diameter)
        )
    }
}

struct PS1InsertFrame {
    let time: Double
    let lift: Double
    let pitch: Double
    let lid: Double
    let open: Double
    let power: Double
    let led: Double
    let spin: Double
    let jolt: Double

    private static let apex = 740.0
    private static let lidRise = 560.0
    private static let lidSpring = Spring(response: 0.42, dampingRatio: 0.72)
    private static let drop = InsertBeat(start: 1000, end: 1150, curve: Motion.insertGravity)
    private static let bounceTop = 1180.0
    private static let settled = 1210.0
    private static let spinUp = InsertBeat(start: 1160, end: 1480, curve: Motion.insertIn)
    private static let shut = InsertBeat(start: 1240, end: 1340, curve: Motion.insertShut)
    private static let openKeys = [
        InsertKey(520, 1, Motion.insertOut),
        InsertKey(560, 0.92, Motion.insertOut),
        InsertKey(620, 1, .linear),
    ]
    private static let powerKeys = [
        InsertKey(1420, 1, Motion.insertOut),
        InsertKey(1450, 0.92, Motion.insertOut),
        InsertKey(1500, 0.95, .linear),
    ]
    private static let joltKeys = [
        InsertKey(1340, 0, Motion.insertOut),
        InsertKey(1360, 3, Motion.insertOut),
        InsertKey(1410, 0, .linear),
    ]

    init(time: Double) {
        self.time = time
        lift = ConsoleStage.lift(at: time)
        pitch = ConsoleStage.pitch(at: time)
        let opened = time < Self.lidRise
            ? 0
            : Self.lidSpring.value(target: 1.0, time: (time - Self.lidRise) / 1000)
        lid = PS1Shape.lidOpen * (time < Self.shut.start ? opened : 1 - Self.shut.progress(time))
        open = InsertFrame.track(time, Self.openKeys)
        power = InsertFrame.track(time, Self.powerKeys)
        led = ConsoleBeat.led.progress(time)
        spin = PS1Disc.spin * Self.spinUp.progress(time)
        jolt = InsertFrame.track(time, Self.joltKeys)
    }

    var cartInBox: Bool {
        time < ConsoleBeat.handoff
    }

    func disc(from handoff: PS1DiscPose) -> PS1DiscPose {
        let mm = ConsoleStage.unit
        let x = (PS1Shape.lidX - PS1Shape.width / 2) * mm
        let depth = PS1Shape.lidZ * mm
        let flat = { (y: Double) in
            PS1DiscPose(offset: [x, ConsoleStage.pivotY + y * mm - ConsoleStage.mid.y, depth], tilt: 90, scale: 1)
        }
        let hover = flat(PS1Shape.rest - PS1Shape.hover)
        let seated = flat(PS1Shape.rest)
        let apex = PS1DiscPose(
            offset: [x / 2, hover.offset.y - PS1Disc.apexRise * mm, depth / 2 + PS1Disc.apexForward * mm],
            tilt: PS1Disc.apexTilt,
            scale: 1
        )
        return PoseKey.pose(at: time, [
            PoseKey(time: ConsoleBeat.handoff, pose: handoff, curve: Motion.insertOut),
            PoseKey(time: Self.apex, pose: apex, curve: Motion.insertInOut),
            PoseKey(time: Self.drop.start, pose: hover, curve: Self.drop.curve),
            PoseKey(time: Self.drop.end, pose: seated, curve: Motion.insertOut),
            PoseKey(time: Self.bounceTop, pose: flat(PS1Shape.rest - PS1Disc.bounce), curve: Motion.insertIn),
            PoseKey(time: Self.settled, pose: seated, curve: .linear),
        ])
    }

    func ledLens(_ geometry: InsertGeometry) -> CGRect {
        let camera = ConsoleCamera(geometry: geometry, pitch: pitch)
        let rig = ConsoleRig(width: PS1Shape.width, lift: lift)
        let led = PS1Shape.led
        let back = -PS1Shape.depth
        return camera.bounds([
            rig.point(SIMD3(led.minX, 0, back + led.minY)),
            rig.point(SIMD3(led.maxX, 0, back + led.minY)),
            rig.point(SIMD3(led.minX, 0, back + led.maxY)),
            rig.point(SIMD3(led.maxX, 0, back + led.maxY)),
        ])
    }

    func flashCenter(_ geometry: InsertGeometry) -> CGPoint {
        let camera = ConsoleCamera(geometry: geometry, pitch: ConsoleStage.pitch)
        return camera.screen(ConsoleRig(width: PS1Shape.width, lift: 0).point(SIMD3(PS1Shape.lidX, 0, PS1Shape.lidZ)))
    }
}

extension InsertGeometry {
    var discHandoff: (offset: SIMD3<Double>, scale: Double) {
        let camera = ConsoleCamera(geometry: self)
        let lifted = CGPoint(x: caseSize.width / 2, y: media.midY - PS1Disc.boxRise * caseSize.height)
        let center = camera.stage(glided(lifted))
        let drawn = Double(media.width * glidedScale) / camera.scale
        return (
            [center.x - ConsoleStage.mid.x, center.y - ConsoleStage.mid.y, 0],
            drawn / (PS1Disc.diameter * ConsoleStage.unit)
        )
    }
}

struct PS1ConsoleScene: View {
    let title: String
    let art: TileArt
    let frame: PS1InsertFrame
    let geometry: InsertGeometry

    var body: some View {
        let camera = ConsoleCamera(geometry: geometry, pitch: frame.pitch)
        let rig = ConsoleRig(width: PS1Shape.width, lift: frame.lift)
        let disc = frame.cartInBox ? nil : frame.disc(from: handoff)
        let sunk = disc.map { $0.offset.y + ConsoleStage.mid.y > ConsoleStage.pivotY + frame.lift } ?? false
        ZStack(alignment: .topLeading) {
            ConsoleFloorShadow(rig: rig, camera: camera, depth: PS1Shape.depth, height: PS1Shape.height)
            wellFloor(rig, camera)
            if let disc, sunk {
                discFace(disc, camera)
            }
            PS1ConsoleShell(rig: rig, camera: camera, open: frame.open, power: frame.power, led: frame.led)
            PS1ConsoleLid(rig: rig, camera: camera, angle: frame.lid)
            if let disc, !sunk {
                discFace(disc, camera)
            }
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height, alignment: .topLeading)
        .offset(y: frame.jolt * camera.scale)
    }

    private var handoff: PS1DiscPose {
        let start = geometry.discHandoff
        return PS1DiscPose(offset: start.offset, tilt: 0, scale: start.scale)
    }

    private func wellFloor(_ rig: ConsoleRig, _ camera: ConsoleCamera) -> some View {
        let radius = PS1Shape.lidRadius
        return ProjectedFace(
            face: rig.face(
                SIMD3(PS1Shape.lidX - radius, PS1Shape.well, PS1Shape.lidZ - radius) * ConsoleStage.unit,
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(2 * radius, 2 * radius)
            ),
            camera: camera
        ) {
            PS1Well()
        }
    }

    private func discFace(_ pose: PS1DiscPose, _ camera: ConsoleCamera) -> some View {
        ProjectedFace(face: pose.face, camera: camera) {
            GameMedia(title: title, system: .ps1, art: art)
                .rotationEffect(.degrees(frame.spin))
        }
    }
}

struct PS1ConsoleShell: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let open: Double
    let power: Double
    let led: Double

    var body: some View {
        let mm = ConsoleStage.unit
        let reach = PS1Shape.blockReach
        let blockSide = ConsoleStage.size(reach, PS1Shape.blockHeight)
        ZStack(alignment: .topLeading) {
            ProjectedFace(
                face: rig.face(
                    SIMD3(0, 0, -PS1Shape.depth * mm),
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(PS1Shape.width, PS1Shape.depth)
                ),
                camera: camera,
                shade: 0.02
            ) {
                PS1Top(open: open, power: power, led: led)
            }
            ProjectedFace(
                face: rig.face(
                    .zero,
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(PS1Shape.width, PS1Shape.height)
                ),
                camera: camera,
                shade: 0.1
            ) {
                PS1Front()
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(PS1Shape.blockLeft, PS1Shape.blockTop, 0) * mm,
                    ConsoleAxis.right,
                    ConsoleAxis.front,
                    ConsoleStage.size(PS1Shape.blockWidth, reach)
                ),
                camera: camera,
                shade: 0.02
            ) {
                PS1BlockTop()
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(PS1Shape.blockLeft, PS1Shape.blockTop, reach) * mm,
                    ConsoleAxis.right,
                    ConsoleAxis.down,
                    ConsoleStage.size(PS1Shape.blockWidth, PS1Shape.blockHeight)
                ),
                camera: camera,
                shade: 0.1
            ) {
                PS1BlockFront()
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(PS1Shape.blockLeft, PS1Shape.blockTop, 0) * mm,
                    ConsoleAxis.front,
                    ConsoleAxis.down,
                    blockSide
                ),
                camera: camera,
                shade: 0.25
            ) {
                PS1Ink.shellShade
            }
            ProjectedFace(
                face: rig.face(
                    SIMD3(PS1Shape.blockRight, PS1Shape.blockTop, reach) * mm,
                    -ConsoleAxis.front,
                    ConsoleAxis.down,
                    blockSide
                ),
                camera: camera,
                shade: 0.25
            ) {
                PS1Ink.shellShade
            }
        }
    }
}

struct PS1ConsoleLid: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let angle: Double

    var body: some View {
        let radius = PS1Shape.lidRadius
        let size = ConsoleStage.size(2 * radius, 2 * radius)
        let hinge = rig.hinge(
            SIMD3(PS1Shape.lidX - radius, -PS1Shape.lidRaise, PS1Shape.lidZ - radius),
            angle
        )
        ZStack(alignment: .topLeading) {
            ProjectedFace(face: hinge.face(.zero, ConsoleAxis.right, ConsoleAxis.front, size), camera: camera) {
                PS1LidTop()
            }
            ProjectedFace(
                face: hinge.face(
                    SIMD3(0, PS1Shape.lidThickness, 2 * radius) * ConsoleStage.unit,
                    ConsoleAxis.right,
                    -ConsoleAxis.front,
                    size
                ),
                camera: camera
            ) {
                PS1LidUnder()
            }
        }
    }
}
