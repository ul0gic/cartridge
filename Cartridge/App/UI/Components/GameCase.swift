import SwiftUI

struct CaseProfile {
    enum Kind {
        case cardboard
        case clamshell
        case jewel
        case keep
    }

    let kind: Kind
    let aspect: CGFloat
    let depth: CGFloat
    let sheen: Double

    var cornerRadius: CGFloat {
        switch kind {
        case .cardboard: 2
        case .clamshell: 7
        case .jewel: 3
        case .keep: 6
        }
    }
}

extension GameSystem {
    var caseProfile: CaseProfile {
        switch self {
        case .nes: CaseProfile(kind: .cardboard, aspect: tileAspect, depth: 0.174, sheen: 0.1)
        case .snes: CaseProfile(kind: .cardboard, aspect: tileAspect, depth: 0.27, sheen: 0.1)
        case .n64: CaseProfile(kind: .cardboard, aspect: tileAspect, depth: 0.3, sheen: 0.12)
        case .genesis: CaseProfile(kind: .clamshell, aspect: tileAspect, depth: 0.142, sheen: 0.26)
        case .ps1: CaseProfile(kind: .jewel, aspect: 142.0 / 125, depth: 0.08, sheen: 0.36)
        case .xbox: CaseProfile(kind: .keep, aspect: tileAspect, depth: 0.079, sheen: 0.26)
        }
    }
}

struct GameCase: View {
    let title: String
    let system: GameSystem
    let art: TileArt
    let height: CGFloat
    let camera: CGFloat
    let tilt: MenuTilt
    var insert = CaseInsertPose.rest

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tints: CaseTints?
    @State private var drift = 1.0

    private static let restPitch = -8.0
    private static let yawReach = 36.0
    private static let pitchReach = 8.0

    var body: some View {
        let profile = system.caseProfile
        let look = CaseLook(
            title: title,
            system: system,
            art: art,
            profile: profile,
            tints: profile.kind == .keep ? .xbox : tints ?? .loading,
            size: CGSize(width: height * profile.aspect, height: height),
            camera: camera
        )
        PosedCase(
            yaw: tilt.x * Self.yawReach,
            pitch: Self.restPitch + tilt.y * Self.pitchReach,
            drift: reduceMotion ? 0 : drift,
            look: look,
            insert: insert
        )
        .animation(Motion.caseTilt, value: tilt)
        .task(id: art) {
            guard case .image(let loaded) = art else {
                tints = nil
                return
            }
            tints = await ArtDecoder.edgeColors(of: loaded.image).map { CaseTints(edges: $0, kind: profile.kind) }
        }
        .task(id: tilt == .zero) {
            guard tilt == .zero else {
                withAnimation(Motion.caseTilt) { drift = 0 }
                return
            }
            guard drift == 0 else { return }
            try? await Task.sleep(for: Motion.caseDriftDelay)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.caseDriftIn) { drift = 1 }
        }
    }
}

struct CaseLook {
    let title: String
    let system: GameSystem
    let art: TileArt
    let profile: CaseProfile
    let tints: CaseTints
    let size: CGSize
    let camera: CGFloat

    var depth: CGFloat {
        size.height * profile.depth
    }
}

@Animatable
private struct PosedCase: View {
    var yaw: Double
    var pitch: Double
    var drift: Double
    @AnimatableIgnored var look: CaseLook
    @AnimatableIgnored var insert: CaseInsertPose

    private static let yawSway = 14.0
    private static let pitchSway = 2.0

    var body: some View {
        TimelineView(.animation(paused: drift == 0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let live = 1 - insert.square
            let pose = CasePose(
                yaw: live * (yaw + drift * Self.yawSway * sin(2 * .pi * time / Motion.caseDriftYawPeriod)),
                pitch: live * (pitch + drift * Self.pitchSway * sin(2 * .pi * time / Motion.caseDriftPitchPeriod)),
                shift: insert.shift
            )
            CaseBody(look: look, pose: pose, insert: insert)
                .background(alignment: .top) {
                    CaseFloor(look: look, pose: pose, insert: insert)
                        .opacity(insert.floor)
                }
        }
    }
}

struct CaseInsertPose {
    var square = 0.0
    var flap = 1.0
    var lid = 0.0
    var lidShade = 0.0
    var fade = 1.0
    var shift = SIMD3<Double>.zero
    var floor = 1.0
    var discInTray = false

    static let rest = CaseInsertPose()
}

struct CasePose {
    let yaw: Double
    let pitch: Double
    var shift = SIMD3<Double>.zero

    func rotated(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let yawRadians = yaw * .pi / 180
        let pitchRadians = pitch * .pi / 180
        let turnedX = vector.x * cos(yawRadians) + vector.z * sin(yawRadians)
        let turnedZ = -vector.x * sin(yawRadians) + vector.z * cos(yawRadians)
        return SIMD3(
            turnedX,
            vector.y * cos(pitchRadians) - turnedZ * sin(pitchRadians),
            vector.y * sin(pitchRadians) + turnedZ * cos(pitchRadians)
        )
    }
}

private enum CaseSide: CaseIterable {
    case tray
    case spine
    case right
    case top
    case front

    func face(_ look: CaseLook, opening: Double) -> CaseFace {
        let size = look.size
        let depth = look.depth
        let edge = CGSize(width: depth, height: size.height)
        let lid = CGSize(width: size.width, height: depth)
        return switch self {
        case .tray: CaseFace(turn: CasePose(yaw: 0, pitch: 0), distance: 1 - depth / 2, size: size)
        case .spine: CaseFace(turn: CasePose(yaw: -90, pitch: 0), distance: size.width / 2, size: edge)
        case .right: CaseFace(turn: CasePose(yaw: 90, pitch: 0), distance: size.width / 2, size: edge)
        case .top: CaseFace(turn: CasePose(yaw: 0, pitch: 90), distance: size.height / 2, size: lid)
        case .front: CaseFace(turn: CasePose(yaw: 0, pitch: 0), distance: depth / 2, size: size).swung(opening)
        }
    }
}

private struct CaseFace {
    let center: SIMD3<Double>
    let across: SIMD3<Double>
    let down: SIMD3<Double>
    let normal: SIMD3<Double>
    let size: CGSize

    init(turn: CasePose, distance: Double, size: CGSize) {
        center = turn.rotated([0, 0, distance])
        across = turn.rotated([1, 0, 0])
        down = turn.rotated([0, 1, 0])
        normal = turn.rotated([0, 0, 1])
        self.size = size
    }

    private init(
        center: SIMD3<Double>,
        across: SIMD3<Double>,
        down: SIMD3<Double>,
        normal: SIMD3<Double>,
        size: CGSize
    ) {
        self.center = center
        self.across = across
        self.down = down
        self.normal = normal
        self.size = size
    }

    func swung(_ degrees: Double) -> CaseFace {
        guard degrees != 0 else { return self }
        let hinge = center - across * size.width / 2
        let turn = CasePose(yaw: degrees, pitch: 0)
        return CaseFace(
            center: hinge + turn.rotated(center - hinge),
            across: turn.rotated(across),
            down: turn.rotated(down),
            normal: turn.rotated(normal),
            size: size
        )
    }

    private static let light: SIMD3<Double> = {
        let raw = SIMD3(-0.35, -0.45, 0.82)
        return raw / (raw * raw).sum().squareRoot()
    }()

    private static let darkest = 0.55

    func shade(_ pose: CasePose) -> Double {
        Self.darkest * (1 - max(0, (pose.rotated(normal) * Self.light).sum()))
    }

    func projection(_ pose: CasePose, eyeY: Double, camera: Double, twoSided: Bool) -> ProjectionTransform? {
        let center = pose.rotated(center) + pose.shift
        guard twoSided || (pose.rotated(normal) * (SIMD3(0, eyeY, camera) - center)).sum() > 0 else { return nil }
        let across = pose.rotated(across)
        let down = pose.rotated(down)
        let origin = center - across * size.width / 2 - down * size.height / 2
        let pivotX = size.width / 2
        let pivotY = eyeY + size.height / 2
        var transform = ProjectionTransform()
        transform.m11 = across.x - pivotX * across.z / camera
        transform.m12 = across.y - pivotY * across.z / camera
        transform.m13 = -across.z / camera
        transform.m21 = down.x - pivotX * down.z / camera
        transform.m22 = down.y - pivotY * down.z / camera
        transform.m23 = -down.z / camera
        transform.m31 = origin.x + pivotX * (1 - origin.z / camera)
        transform.m32 = origin.y - eyeY + pivotY * (1 - origin.z / camera)
        transform.m33 = 1 - origin.z / camera
        return transform
    }
}

private struct CaseBody: View {
    let look: CaseLook
    let pose: CasePose
    let insert: CaseInsertPose

    var body: some View {
        let eyeY = -look.size.height * (0.5 + Layout.caseEyeLift)
        ZStack {
            ForEach(CaseSide.allCases, id: \.self) { side in
                let face = side.face(look, opening: insert.lid)
                let drawn = side != .tray || look.profile.kind == .jewel || look.profile.kind == .keep
                let swung = side == .front && insert.lid != 0
                if drawn, let projection = face.projection(pose, eyeY: eyeY, camera: look.camera, twoSided: swung) {
                    let inside = swung && look.profile.kind == .keep
                        && face.projection(pose, eyeY: eyeY, camera: look.camera, twoSided: false) == nil
                    content(side, inside: inside)
                        .frame(width: face.size.width, height: face.size.height)
                        .overlay(Color.black.opacity(swung ? max(face.shade(pose), insert.lidShade) : face.shade(pose)))
                        .clipShape(RoundedRectangle(cornerRadius: look.profile.cornerRadius))
                        .opacity(side == .top ? insert.flap * insert.fade : insert.fade)
                        .projectionEffect(projection)
                }
            }
        }
        .frame(width: look.size.width, height: look.size.height)
    }

    @ViewBuilder
    private func content(_ side: CaseSide, inside: Bool) -> some View {
        switch side {
        case .tray:
            ZStack(alignment: .topLeading) {
                if look.profile.kind == .keep {
                    CaseKeepTray(size: look.size)
                } else {
                    CaseMaterial.trayPlastic
                }
                if insert.discInTray {
                    let disc = look.system.mediaRect(in: look.size)
                    GameMedia(title: look.title, system: look.system, art: look.art)
                        .frame(width: disc.width, height: disc.height)
                        .offset(x: disc.minX, y: disc.minY)
                }
            }
        case .spine: CaseSpine(look: look)
        case .right: CaseEdge(look: look, tint: look.tints.right, seam: true)
        case .top: CaseEdge(look: look, tint: look.tints.top, seam: false)
        case .front:
            if inside {
                CaseCoverInside()
            } else {
                CaseFront(look: look, pose: pose)
            }
        }
    }
}

private struct CaseFloor: View {
    let look: CaseLook
    let pose: CasePose
    let insert: CaseInsertPose

    private static let poolRadiusShare = 0.6
    private static let poolCenterShare = 0.12

    var body: some View {
        let width = look.size.width
        let height = look.size.height
        let poolDepth = Layout.casePoolDepth
        let poolSpan = poolDepth * 2 * Self.poolRadiusShare
        ZStack(alignment: .top) {
            EllipticalGradient(
                colors: [.black.opacity(0.6), .clear],
                center: UnitPoint(x: 0.5, y: Self.poolCenterShare * poolDepth / poolSpan)
            )
            .frame(width: width * 3.2, height: poolSpan)
            .frame(height: poolDepth, alignment: .top)
            .clipped()
            .offset(y: height - Layout.casePoolLift)
            LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 3.2 * 0.64, height: 1)
                .offset(y: height)
            CaseBody(look: look, pose: pose, insert: insert)
                .scaleEffect(x: 1, y: -1)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.3), location: 0),
                            .init(color: .clear, location: 0.46),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .padding(.horizontal, -width)
                }
                .offset(y: height)
            EllipticalGradient(colors: [.black.opacity(0.7), .clear])
                .frame(width: width * 1.1, height: Layout.caseContactHeight)
                .blur(radius: Layout.caseContactBlur)
                .offset(y: height - Layout.caseContactHeight / 2)
        }
    }
}

struct CaseTints {
    let spine: Color
    let top: Color
    let right: Color
    let ink: Color

    static let xbox = CaseTints(
        spine: CaseMaterial.xboxPlastic,
        top: CaseMaterial.xboxPlastic,
        right: CaseMaterial.xboxPlastic,
        ink: .white
    )

    static let loading = CaseTints(
        spine: Palette.tileLoading,
        top: Palette.tileLoading,
        right: Palette.tileLoading,
        ink: Palette.textOnArt
    )
}

extension CaseTints {
    init(edges: ArtEdgeColors, kind: CaseProfile.Kind) {
        let spine = kind == .cardboard ? edges.left * 0.8 : edges.left
        self.init(
            spine: Self.color(spine),
            top: Self.color(edges.top * 0.7),
            right: Self.color(edges.right * 0.65),
            ink: Self.luminance(spine) > 0.45 ? CaseMaterial.darkInk : .white
        )
    }

    private static func color(_ rgb: SIMD3<Double>) -> Color {
        Color(.sRGB, red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    private static func luminance(_ rgb: SIMD3<Double>) -> Double {
        let linear = [rgb.x, rgb.y, rgb.z].map { $0 <= 0.039_28 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
