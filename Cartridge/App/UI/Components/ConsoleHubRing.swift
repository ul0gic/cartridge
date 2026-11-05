import QuartzCore
import SwiftUI

private enum Ring {
    static let stage = CGSize(width: 1440, height: 900)
    static let center = CGPoint(x: 720, y: 700)
    static let card = CGSize(width: 420, height: 236)
    static let radiusX = 640.0
    static let depth = 300.0
    static let camera = 1000.0
    static let rise = 0.45
    static let frontScale = 0.9
    static let referenceCount = 5.0
    static let radiusExponent = 0.2
    static let frontExponent = 0.25
    static let twist = 0.36
    static let dim = 0.3
    static let neighbourBrightness = 0.58
    static let neighbourBlur = 2.4
    static let maxBlur = 7.0
    static let seamFade = 0.35
    static let reflectionGap: CGFloat = 10
    static let reflectionOpacity = 0.3
    static let reflectionFade = 0.42
    static let consoleBox = CGSize(width: 520, height: 280)
    static let pedestal = CGSize(width: 560, height: 96)
    static let consoleDrop = pedestal.height * 0.12
    static let glowSpread: CGFloat = 20
    static let floor = CGSize(width: 1240, height: 260)
    static let floorY: CGFloat = 840
    static let sink: CGFloat = 18
    static let swapScale: CGFloat = 0.9
    static let contactWidthShare: CGFloat = 0.88
    static let contactHeight: CGFloat = 46
    static let contactDrop: CGFloat = 28
    static let contactBlur: CGFloat = 6
    static let glowBlur: CGFloat = 30
    static let consoleShadowBlur: CGFloat = 18
    static let consoleShadowDrop: CGFloat = 14
    static let hub = CGPoint(x: center.x, y: center.y - rise * depth)
}

private struct RingPlacement {
    let offset: CGSize
    let scale: CGFloat
    let turn: Double
    let brightness: Double
    let blur: CGFloat
    let opacity: Double
    let depth: Double

    init(index: Int, position: Double, count: Int) {
        let total = Double(count)
        let half = total / 2
        var wrapped = (Double(index) - position + half).truncatingRemainder(dividingBy: total)
        if wrapped < 0 {
            wrapped += total
        }
        let distance = wrapped - half
        let step = 2 * Double.pi / total
        let angle = distance * step
        let light = (1 + cos(angle)) / 2
        let neighbourLight = (1 + cos(step)) / 2
        let gamma = log((Ring.neighbourBrightness - Ring.dim) / (1 - Ring.dim)) / log(neighbourLight)
        let radiusX = Ring.radiusX * pow(total / Ring.referenceCount, Ring.radiusExponent)
        let front = Ring.frontScale * pow(Ring.referenceCount / total, Ring.frontExponent)
        let depth = Ring.depth * (1 - cos(angle))
        let perspective = Ring.camera / (Ring.camera + depth)
        offset = CGSize(
            width: Ring.center.x - Ring.stage.width / 2 + radiusX * sin(angle) * perspective,
            height: Ring.center.y - Ring.stage.height / 2 - Ring.rise * depth
        )
        scale = front * perspective
        turn = Ring.twist * angle
        brightness = Ring.dim + (1 - Ring.dim) * pow(light, gamma)
        blur = count > 1 ? min(Ring.maxBlur, Ring.neighbourBlur * (1 - light) / (1 - neighbourLight)) : 0
        opacity = min(1, max(0, (half - abs(distance)) / Ring.seamFade))
        self.depth = depth
    }

    var projection: ProjectionTransform {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / Ring.camera
        let centred = CATransform3DMakeTranslation(-Ring.card.width / 2, -Ring.card.height / 2, 0)
        let turned = CATransform3DRotate(perspective, turn, 0, 1, 0)
        let back = CATransform3DMakeTranslation(Ring.card.width / 2, Ring.card.height / 2, 0)
        return ProjectionTransform(CATransform3DConcat(CATransform3DConcat(centred, turned), back))
    }
}

@Animatable
struct ConsoleHubRing: View {
    var position: Double
    @AnimatableIgnored var model: AppModel
    @AnimatableIgnored var consoles: [ConsoleSummary]
    @AnimatableIgnored var focused: Int?
    @AnimatableIgnored var hubSystem: GameSystem?
    @AnimatableIgnored var ghost: Double?
    @AnimatableIgnored var dissolve: Int
    @AnimatableIgnored var reduceMotion: Bool

    static func step(from old: Int, to new: Int, count: Int) -> Int {
        let forward = ((new - old) % count + count) % count
        return forward * 2 > count ? forward - count : forward
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RingFloor()
                ring
            }
            .frame(width: Ring.stage.width, height: Ring.stage.height)
            .scaleEffect(proxy.size.width / Ring.stage.width, anchor: .bottom)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
    }

    private var ring: some View {
        ZStack {
            ForEach(consoles.indices, id: \.self) { index in
                placed(index, at: position, highlighted: index == focused, resting: 1)
            }
            if reduceMotion, let ghost {
                ForEach(consoles.indices, id: \.self) { index in
                    placed(index, at: ghost, highlighted: false, resting: 0)
                        .accessibilityHidden(true)
                }
            }
            if let hubSystem {
                RingPedestal(system: hubSystem)
                    .offset(x: Ring.hub.x - Ring.stage.width / 2, y: Ring.hub.y - Ring.stage.height / 2)
                    .zIndex(-Ring.depth)
                RingConsole(system: hubSystem)
                    .offset(
                        x: Ring.hub.x - Ring.stage.width / 2,
                        y: Ring.hub.y + Ring.consoleDrop - Ring.consoleBox.height / 2
                            - Ring.stage.height / 2
                    )
                    .id(hubSystem)
                    .transition(consoleSwap)
                    .zIndex(-Ring.depth)
            }
        }
    }

    private func placed(_ index: Int, at position: Double, highlighted: Bool, resting: Double) -> some View {
        let placement = RingPlacement(index: index, position: position, count: consoles.count)
        return RingCard(model: model, summary: consoles[index], isHighlighted: highlighted)
            .colorMultiply(Color(white: placement.brightness))
            .blur(radius: placement.blur)
            .projectionEffect(placement.projection)
            .scaleEffect(placement.scale)
            .offset(placement.offset)
            .opacity(placement.opacity)
            .keyframeAnimator(initialValue: resting, trigger: dissolve) { content, fade in
                content.opacity(fade)
            } keyframes: { _ in
                MoveKeyframe(1 - resting)
                LinearKeyframe(resting, duration: Motion.handover.seconds)
            }
            .zIndex(-placement.depth)
    }

    private var consoleSwap: AnyTransition {
        if reduceMotion {
            return .asymmetric(
                insertion: .opacity.animation(.linear(duration: Motion.handover.seconds)),
                removal: .opacity.animation(Motion.easeIn(Motion.focus))
            )
        }
        let sunk = AnyTransition.opacity
            .combined(with: .offset(y: Ring.sink))
            .combined(with: .scale(scale: Ring.swapScale))
        return .asymmetric(
            insertion: sunk.animation(Motion.ringConsoleRise.delay(Motion.focus.seconds / 2)),
            removal: sunk.animation(Motion.easeIn(Motion.focus))
        )
    }
}

private struct RingCard: View {
    let model: AppModel
    let summary: ConsoleSummary
    let isHighlighted: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            reflection
            contactShadow
            card(isHighlighted: isHighlighted)
        }
    }

    private func card(isHighlighted: Bool) -> ConsoleCard {
        ConsoleCard(
            model: model,
            summary: summary,
            isHighlighted: isHighlighted,
            width: Ring.card.width,
            height: Ring.card.height,
            focusScale: 1
        )
    }

    private var reflection: some View {
        card(isHighlighted: false)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 1 - Ring.reflectionFade),
                        .init(color: .black.opacity(Ring.reflectionOpacity), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .scaleEffect(x: 1, y: -1, anchor: .bottom)
            .offset(y: Ring.reflectionGap)
            .accessibilityHidden(true)
    }

    private var contactShadow: some View {
        EllipticalGradient(colors: [.black.opacity(0.7), .clear])
            .frame(width: Ring.card.width * Ring.contactWidthShare, height: Ring.contactHeight)
            .blur(radius: Ring.contactBlur)
            .offset(y: Ring.contactDrop)
    }
}

private struct RingPedestal: View {
    let system: GameSystem

    var body: some View {
        let light = ConsolePalette.of(system).light
        ZStack {
            ZStack {
                Ellipse()
                    .fill(light.opacity(0.22))
                    .frame(
                        width: Ring.pedestal.width + Ring.glowSpread,
                        height: Ring.pedestal.height + Ring.glowSpread
                    )
                    .blur(radius: Ring.glowBlur)
                Ellipse()
                    .frame(width: Ring.pedestal.width, height: Ring.pedestal.height)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            EllipticalGradient(stops: [
                .init(color: .white.opacity(0.08), location: 0),
                .init(color: .black.opacity(0.55), location: 0.7),
                .init(color: .clear, location: 1),
            ])
            EllipticalGradient(stops: [
                .init(color: light.opacity(0.55), location: 0),
                .init(color: light.opacity(0), location: 0.75),
            ])
        }
        .frame(width: Ring.pedestal.width, height: Ring.pedestal.height)
        .animation(Motion.easeInOut(Motion.ambient), value: system)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RingConsole: View {
    let system: GameSystem

    var body: some View {
        Image(system.cutoutImage)
            .resizable()
            .scaledToFit()
            .frame(width: Ring.consoleBox.width, height: Ring.consoleBox.height, alignment: .bottom)
            .shadow(color: .black.opacity(0.6), radius: Ring.consoleShadowBlur, y: Ring.consoleShadowDrop)
            .accessibilityHidden(true)
    }
}

private struct RingFloor: View {
    var body: some View {
        EllipticalGradient(stops: [
            .init(color: .black.opacity(0.62), location: 0),
            .init(color: .black.opacity(0.3), location: 0.55),
            .init(color: .clear, location: 1),
        ])
        .frame(width: Ring.floor.width, height: Ring.floor.height)
        .offset(y: Ring.floorY - Ring.stage.height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
