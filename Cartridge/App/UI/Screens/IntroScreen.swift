import SwiftUI

struct IntroScreen: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var skipOffset: TimeInterval = 0
    @State private var lockupSize = CGSize.zero

    var body: some View {
        TimelineView(.animation) { context in
            let time = (start.map { context.date.timeIntervalSince($0) } ?? 0) + skipOffset
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Color.black
                    if !reduceMotion {
                        ImpactBurst(strength: impact(time))
                    }
                    lockup(time: time)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { lockupSize = $0 }
                        .scaleEffect(scale(time) * (1 + 0.05 * pop(time)), anchor: .leading)
                        .offset(lockupOffset(time: time, in: proxy.size))
                    if model.isAwaitingLibrary {
                        LoadingLine()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, Space.n9)
                    }
                }
            }
            .onChange(of: time >= endTime) { _, finished in
                if finished {
                    model.introDidFinish()
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: model.introSkips) {
            let now = Date.now
            let elapsed = (start.map { now.timeIntervalSince($0) } ?? 0) + skipOffset
            if start == nil {
                start = now
            }
            if elapsed < glideStart {
                UISound.fadeOut(.intro)
            }
            skipOffset += max(0, glideStart - elapsed)
        }
        .onAppear(perform: begin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cartridge")
    }

    private var endTime: TimeInterval {
        reduceMotion ? Motion.introReducedEnd : Motion.introEnd
    }

    private var glideStart: TimeInterval {
        reduceMotion ? Motion.introReducedEnd : Motion.introGlide
    }

    private func begin() {
        start = .now
        UISound.play(.intro)
    }

    private func lockup(time: TimeInterval) -> some View {
        HStack(spacing: Space.n2 * IntroLockup.factor) {
            AppIconImage(size: IntroLockup.icon)
                .shadow(color: Palette.brand3.opacity(0.7), radius: 40)
                .scaleEffect(reduceMotion ? 1 : 0.9 + 0.1 * IntroTiming.afterSting(time, 0, 0.22))
                .opacity(reduceMotion ? IntroTiming.ramp(time, 0, 0.6) : IntroTiming.afterSting(time, 0, 0.06))
            Text("Cartridge")
                .typeStyle(IntroLockup.wordmark)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize()
                .mask(alignment: .leading) {
                    GeometryReader { text in
                        Rectangle().frame(width: text.size.width * wordmarkReveal(time))
                    }
                }
                .shadow(color: Palette.brand2.opacity(0.6 * (1 - glide(time))), radius: 30)
        }
        .fixedSize()
    }

    private func wordmarkReveal(_ time: TimeInterval) -> CGFloat {
        reduceMotion ? IntroTiming.ramp(time, 0.5, 1.0) : IntroTiming.afterSting(time, 0.05, 0.45)
    }

    private func impact(_ time: TimeInterval) -> CGFloat {
        IntroTiming.afterSting(time, 0.02, 0.1)
            * (1 - IntroTiming.afterSting(time, 0.15, 1.2))
    }

    private func pop(_ time: TimeInterval) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return IntroTiming.afterSting(time, 0.02, 0.1)
            * (1 - IntroTiming.afterSting(time, 0.1, 0.55))
    }

    private func glide(_ time: TimeInterval) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let raw = IntroTiming.ramp(time, Motion.introGlide, Motion.introEnd - 0.05)
        return raw * raw * (3 - 2 * raw)
    }

    private func scale(_ time: TimeInterval) -> CGFloat {
        1 - (1 - 1 / IntroLockup.factor) * glide(time)
    }

    private func lockupOffset(time: TimeInterval, in size: CGSize) -> CGSize {
        let startX = (size.width - lockupSize.width) / 2
        let startY = size.height / 2 - lockupSize.height / 2
        let endX = Layout.marginX
        let endY = model.chrome.safeTop + Space.n2 + Layout.topbarHeight / 2 - lockupSize.height / 2
        let progress = glide(time)
        return CGSize(width: startX + (endX - startX) * progress, height: startY + (endY - startY) * progress)
    }
}

enum IntroLockup {
    static let factor: CGFloat = 5
    static let icon = Layout.wordmarkIconSmall * factor
    static let wordmark = TypeStyle(
        size: TypeStyle.topbarWordmark.size * factor,
        weight: .heavy,
        width: .condensed,
        leading: 1.0,
        tracking: -0.01
    )
}

enum IntroTiming {
    static let sting: TimeInterval = 0.2 // intro.m4a's sting starts here

    static func ramp(_ time: TimeInterval, _ from: TimeInterval, _ to: TimeInterval) -> CGFloat {
        CGFloat(min(max((time - from) / (to - from), 0), 1))
    }

    static func afterSting(_ time: TimeInterval, _ from: TimeInterval, _ to: TimeInterval) -> CGFloat {
        ramp(time, sting + from, sting + to)
    }
}

private struct ImpactBurst: View {
    let strength: CGFloat

    var body: some View {
        RadialGradient(
            colors: [Palette.brand3.opacity(0.9), Palette.brand2.opacity(0.45), .clear],
            center: .center,
            startRadius: 0,
            endRadius: Layout.introBurstRadius * (0.6 + 0.4 * strength)
        )
        .blendMode(.screen)
        .opacity(strength)
        .allowsHitTesting(false)
    }
}

private struct LoadingLine: View {
    var body: some View {
        HStack(spacing: Space.n2) {
            Spinner()
            Text("Loading your library")
                .typeStyle(.meta)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
