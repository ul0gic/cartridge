import simd
import SwiftUI

enum ConsoleStage {
    static let mid = SIMD2(720.0, 450.0)
    static let camera = 2600.0
    static let eyeY = 330.0
    static let pivotY = 560.0
    static let pitch = -28.0
    static let rise = 640.0
    static let unit = 2.2
    static let shadowPad = 70.0

    static func size(_ width: Double, _ height: Double) -> CGSize {
        CGSize(width: width * unit, height: height * unit)
    }

    static func lift(at time: Double) -> Double {
        let risen = time < ConsoleBeat.rise
            ? 0
            : Motion.insertConsoleRise.value(target: 1.0, time: (time - ConsoleBeat.rise) / 1000)
        return rise * (1 - risen)
    }

    static func pitch(at time: Double) -> Double {
        pitch * ConsoleBeat.crane.progress(time)
    }
}

enum ConsoleAxis {
    static let right = SIMD3<Double>(1, 0, 0)
    static let down = SIMD3<Double>(0, 1, 0)
    static let front = SIMD3<Double>(0, 0, 1)
}

enum ConsoleInsertFrame {
    case nes(NESInsertFrame)
    case snes(TopLoaderFrame)
    case genesis(TopLoaderFrame)
    case n64(TopLoaderFrame)
    case ps1(PS1InsertFrame)
    case xbox(XboxInsertFrame)

    init?(system: GameSystem, time: Double) {
        switch system {
        case .nes: self = .nes(NESInsertFrame(time: time))
        case .snes: self = .snes(TopLoaderFrame(time: time, console: .snes))
        case .genesis: self = .genesis(TopLoaderFrame(time: time, console: .genesis))
        case .n64: self = .n64(TopLoaderFrame(time: time, console: .n64))
        case .ps1: self = .ps1(PS1InsertFrame(time: time))
        case .xbox: self = .xbox(XboxInsertFrame(time: time))
        }
    }

    var cartInBox: Bool {
        switch self {
        case .nes(let frame): frame.cartInBox
        case .snes(let frame): frame.cartInBox
        case .genesis(let frame): frame.cartInBox
        case .n64(let frame): frame.cartInBox
        case .ps1(let frame): frame.cartInBox
        case .xbox(let frame): frame.cartInBox
        }
    }

    func ledLens(_ geometry: InsertGeometry) -> CGRect {
        switch self {
        case .nes(let frame): frame.ledLens(geometry)
        case .snes(let frame): frame.ledLens(geometry)
        case .genesis(let frame): frame.ledLens(geometry)
        case .n64(let frame): frame.ledLens(geometry)
        case .ps1(let frame): frame.ledLens(geometry)
        case .xbox(let frame): frame.ledLens(geometry)
        }
    }

    var ledRing: Double? {
        guard case .xbox = self else { return nil }
        return XboxShape.ringWidth / (2 * XboxShape.ringRadius)
    }

    func flashCenter(_ geometry: InsertGeometry) -> CGPoint {
        switch self {
        case .nes(let frame): frame.flashCenter(geometry)
        case .snes(let frame): frame.flashCenter(geometry)
        case .genesis(let frame): frame.flashCenter(geometry)
        case .n64(let frame): frame.flashCenter(geometry)
        case .ps1(let frame): frame.flashCenter(geometry)
        case .xbox(let frame): frame.flashCenter(geometry)
        }
    }
}

struct ConsoleScene: View {
    let title: String
    let art: TileArt
    let frame: ConsoleInsertFrame
    let geometry: InsertGeometry

    var body: some View {
        switch frame {
        case .nes(let frame):
            NESConsoleScene(title: title, art: art, frame: frame, geometry: geometry)
        case .snes(let frame):
            TopLoaderScene(title: title, art: art, frame: frame, geometry: geometry) { rig, camera in
                SNESConsoleShell(rig: rig, camera: camera, power: frame.power, led: frame.led)
            }
        case .genesis(let frame):
            TopLoaderScene(title: title, art: art, frame: frame, geometry: geometry) { rig, camera in
                GenesisConsoleShell(rig: rig, camera: camera, power: frame.power, led: frame.led)
            }
        case .n64(let frame):
            TopLoaderScene(title: title, art: art, frame: frame, geometry: geometry) { rig, camera in
                N64ConsoleShell(rig: rig, camera: camera, power: frame.power, led: frame.led)
            }
        case .ps1(let frame):
            PS1ConsoleScene(title: title, art: art, frame: frame, geometry: geometry)
        case .xbox(let frame):
            XboxConsoleScene(title: title, art: art, frame: frame, geometry: geometry)
        }
    }
}

struct ConsoleFace {
    let origin: SIMD3<Double>
    let across: SIMD3<Double>
    let down: SIMD3<Double>
    let size: CGSize
}

struct ConsoleCamera {
    let center: CGPoint
    let scale: Double
    let pitch: Double

    init(geometry: InsertGeometry, pitch: Double = 0) {
        center = CGPoint(x: geometry.canvas.width / 2, y: geometry.canvas.height / 2)
        scale = Double(geometry.scale)
        self.pitch = pitch
    }

    func app(x: Double, y: Double) -> CGPoint {
        CGPoint(
            x: center.x + (x - ConsoleStage.mid.x) * scale,
            y: center.y + (y - ConsoleStage.mid.y) * scale
        )
    }

    func stage(_ point: CGPoint) -> SIMD2<Double> {
        SIMD2(
            ConsoleStage.mid.x + (point.x - center.x) / scale,
            ConsoleStage.mid.y + (point.y - center.y) / scale
        )
    }

    func screen(_ point: SIMD3<Double>) -> CGPoint {
        let pitched = pitched(point)
        let depth = ConsoleStage.camera / (ConsoleStage.camera - pitched.z)
        return app(
            x: ConsoleStage.mid.x + (pitched.x - ConsoleStage.mid.x) * depth,
            y: ConsoleStage.eyeY + (pitched.y - ConsoleStage.eyeY) * depth
        )
    }

    func bounds(_ points: [SIMD3<Double>]) -> CGRect {
        let corners = points.map { CGRect(origin: screen($0), size: .zero) }
        return corners.dropFirst().reduce(corners[0]) { $0.union($1) }
    }

    func projection(_ face: ConsoleFace, twoSided: Bool = false) -> ProjectionTransform? {
        let origin = pitched(face.origin)
        let across = Self.rotated(face.across, degrees: pitch) / scale
        let down = Self.rotated(face.down, degrees: pitch) / scale
        let eye = SIMD3(ConsoleStage.mid.x, ConsoleStage.eyeY, ConsoleStage.camera)
        guard twoSided || dot(cross(across, down), eye - origin) > 0 else { return nil }
        let first = homogeneous(across, 0)
        let second = homogeneous(down, 0)
        let third = homogeneous(origin, 1)
        var transform = ProjectionTransform()
        transform.m11 = first.x
        transform.m12 = first.y
        transform.m13 = first.z
        transform.m21 = second.x
        transform.m22 = second.y
        transform.m23 = second.z
        transform.m31 = third.x
        transform.m32 = third.y
        transform.m33 = third.z
        return transform
    }

    static func rotated(_ vector: SIMD3<Double>, degrees: Double) -> SIMD3<Double> {
        let radians = degrees * .pi / 180
        return SIMD3(
            vector.x,
            vector.y * cos(radians) - vector.z * sin(radians),
            vector.y * sin(radians) + vector.z * cos(radians)
        )
    }

    private func pitched(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let pivot = SIMD3(ConsoleStage.mid.x, ConsoleStage.pivotY, 0)
        return pivot + Self.rotated(point - pivot, degrees: pitch)
    }

    private func homogeneous(_ vector: SIMD3<Double>, _ weight: Double) -> SIMD3<Double> {
        let depth = weight - vector.z / ConsoleStage.camera
        let x = vector.x - ConsoleStage.mid.x * vector.z / ConsoleStage.camera
        let y = vector.y - ConsoleStage.eyeY * vector.z / ConsoleStage.camera
        return SIMD3(
            scale * x + (center.x - scale * ConsoleStage.mid.x) * depth,
            scale * y + (center.y - scale * ConsoleStage.mid.y) * depth,
            depth
        )
    }
}

struct ConsoleRig {
    let width: Double
    let lift: Double

    private var origin: SIMD3<Double> {
        SIMD3(ConsoleStage.mid.x - width * ConsoleStage.unit / 2, ConsoleStage.pivotY + lift, 0)
    }

    func face(_ origin: SIMD3<Double>, _ across: SIMD3<Double>, _ down: SIMD3<Double>, _ size: CGSize) -> ConsoleFace {
        ConsoleFace(origin: self.origin + origin, across: across, down: down, size: size)
    }

    func hinge(_ millimetres: SIMD3<Double>, _ degrees: Double) -> ConsoleHinge {
        ConsoleHinge(origin: origin + millimetres * ConsoleStage.unit, degrees: degrees)
    }

    func point(_ millimetres: SIMD3<Double>) -> SIMD3<Double> {
        origin + millimetres * ConsoleStage.unit
    }
}

struct ConsoleHinge {
    let origin: SIMD3<Double>
    let degrees: Double

    func face(_ origin: SIMD3<Double>, _ across: SIMD3<Double>, _ down: SIMD3<Double>, _ size: CGSize) -> ConsoleFace {
        ConsoleFace(
            origin: self.origin + ConsoleCamera.rotated(origin, degrees: degrees),
            across: ConsoleCamera.rotated(across, degrees: degrees),
            down: ConsoleCamera.rotated(down, degrees: degrees),
            size: size
        )
    }
}

protocol InsertPose {
    func mixed(with other: Self, by amount: Double) -> Self
}

struct PoseKey<Pose: InsertPose> {
    let time: Double
    let pose: Pose
    let curve: UnitCurve

    static func pose(at time: Double, _ keys: [Self]) -> Pose {
        for (from, to) in zip(keys, keys.dropFirst()) where time < to.time {
            guard time > from.time else { return from.pose }
            return from.pose.mixed(with: to.pose, by: from.curve.value(at: (time - from.time) / (to.time - from.time)))
        }
        return keys[keys.count - 1].pose
    }
}

extension InsertGeometry {
    func handoff(width: Double) -> (offset: SIMD3<Double>, scale: Double) {
        let camera = ConsoleCamera(geometry: self)
        let center = camera.stage(glided(CGPoint(x: media.midX, y: media.midY + risenCart)))
        let drawn = Double(media.width * glidedScale) / camera.scale
        return (
            [center.x - ConsoleStage.mid.x, center.y - ConsoleStage.mid.y, 0],
            drawn / (width * ConsoleStage.unit)
        )
    }
}

struct ProjectedFace<Content: View>: View {
    let face: ConsoleFace
    let camera: ConsoleCamera
    var shade = 0.0
    var twoSided = false
    @ViewBuilder let content: Content

    var body: some View {
        if let projection = camera.projection(face, twoSided: twoSided) {
            content
                .frame(width: face.size.width * camera.scale, height: face.size.height * camera.scale)
                .overlay {
                    if shade > 0 {
                        Color.black.opacity(shade)
                    }
                }
                .projectionEffect(projection)
        }
    }
}

struct ConsoleFloorShadow: View {
    let rig: ConsoleRig
    let camera: ConsoleCamera
    let depth: Double
    let height: Double

    var body: some View {
        let pad = ConsoleStage.shadowPad
        ProjectedFace(
            face: rig.face(
                SIMD3(-pad, height, -depth - pad) * ConsoleStage.unit,
                ConsoleAxis.right,
                ConsoleAxis.front,
                ConsoleStage.size(rig.width + 2 * pad, depth + 2 * pad)
            ),
            camera: camera
        ) {
            EllipticalGradient(stops: [
                .init(color: .black.opacity(0.75), location: 0),
                .init(color: .black.opacity(0.375), location: 0.62),
                .init(color: .clear, location: 1),
            ])
        }
    }
}

struct ConsoleSketch {
    let context: GraphicsContext
    let ink: Color

    func fill(_ path: Path, top: Color, bottom: Color, eoFill: Bool = false) {
        let bounds = path.boundingRect
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
            ),
            style: FillStyle(eoFill: eoFill)
        )
    }

    func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
        context.fill(Path(CGRect(x: x, y: y, width: width, height: height)), with: .color(color))
    }

    func word(_ text: String, size: CGFloat, tracking: CGFloat, at point: CGPoint) {
        context.draw(
            Text(text).font(.system(size: size, weight: .bold)).tracking(tracking).foregroundStyle(ink),
            at: point
        )
    }
}

struct ConsoleLED {
    let rect: CGRect
    let off: Color
    let shine: Color
    let color: Color

    func draw(_ on: Double, in context: GraphicsContext, glow: GraphicsContext, unit: CGFloat) {
        let lens = Path(roundedRect: rect, cornerRadius: 0.6)
        context.fill(lens, with: .color(off))
        context.stroke(lens, with: .color(.black.opacity(0.6)), lineWidth: 0.3)
        guard on > 0 else { return }
        var halo = glow
        halo.opacity = 0.85 * on
        halo.addFilter(.blur(radius: 2.4 * unit))
        halo.scaleBy(x: unit, y: unit)
        halo.fill(Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 3), with: .color(color))
        var lit = context
        lit.opacity = on
        lit.fill(lens, with: .color(color))
        lit.fill(
            Path(
                roundedRect: CGRect(x: rect.minX + 0.6, y: rect.minY + 0.3, width: rect.width - 1.2, height: 0.5),
                cornerRadius: 0.25
            ),
            with: .color(shine)
        )
    }
}

struct ConsoleHoldingLight: View {
    let title: String
    let geometry: InsertGeometry
    let held: TimeInterval
    let lens: CGRect
    let ring: Double?
    let color: Color

    var body: some View {
        let pace = InsertSchedule.console.pace
        let phase = (held / (Motion.insertHoldGlow * pace)).truncatingRemainder(dividingBy: 1)
        let glow = (6 + 8 * Motion.insertInOut.value(at: phase < 0.5 ? 2 * phase : 2 - 2 * phase)) * geometry.scale
        let caption = Motion.insertOut.value(
            at: min(1, max(0, (held - Motion.insertCaptionDelay * pace) / Motion.insertCaptionFade))
        )
        ZStack {
            Group {
                if let ring {
                    Circle().stroke(color, lineWidth: ring * lens.width)
                } else {
                    RoundedRectangle(cornerRadius: lens.height / 3).fill(color)
                }
            }
            .shadow(color: color, radius: glow / 2)
            .shadow(color: color.opacity(0.45), radius: 1.5 * glow)
            .frame(width: lens.width, height: lens.height)
            .position(x: lens.midX, y: lens.midY)
            Text("Starting \(title)…")
                .typeStyle(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize()
                .frame(width: 0, alignment: .leading)
                .opacity(caption)
                .position(x: lens.maxX + Layout.panelInsertCaptionGap * geometry.scale, y: lens.midY)
        }
    }
}
