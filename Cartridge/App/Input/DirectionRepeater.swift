import Foundation

@MainActor
final class DirectionRepeater {
    var onEvent: ((NavigationEvent) -> Void)?

    private let source: InputSource
    private var active: Direction?
    private var task: Task<Void, Never>?

    init(source: InputSource) {
        self.source = source
    }

    func press(_ direction: Direction) {
        guard direction != active else { return }
        task?.cancel()
        active = direction
        onEvent?(NavigationEvent(action: .move(direction), source: source, isRepeat: false))
        task = Task { [weak self] in
            let clock = ContinuousClock()
            var next = clock.now.advanced(by: Motion.repeatDelay)
            while true {
                do {
                    try await clock.sleep(until: next)
                } catch {
                    return
                }
                guard let self, active == direction else { return }
                onEvent?(NavigationEvent(action: .move(direction), source: source, isRepeat: true))
                next = next.advanced(by: Motion.repeatInterval)
            }
        }
    }

    func release(_ direction: Direction) {
        guard direction == active else { return }
        releaseAll()
    }

    func releaseAll() {
        task?.cancel()
        task = nil
        active = nil
    }
}

struct StickDirectionResolver {
    struct Transition: Equatable {
        let released: Direction?
        let pressed: Direction?

        static let none = Transition(released: nil, pressed: nil)
    }

    private var current: Direction?
    private var neutralSince: ContinuousClock.Instant?
    private var isArmed = false

    mutating func reset(magnitude: Float?, at now: ContinuousClock.Instant) {
        current = nil
        isArmed = false
        neutralSince = (magnitude ?? 1) < Motion.stickRelease ? now : nil
    }

    mutating func update(x: Float, y: Float, at now: ContinuousClock.Instant) -> Transition {
        let magnitude = max(abs(x), abs(y))
        if let held = current {
            guard magnitude < Motion.stickRelease else { return .none }
            current = nil
            neutralSince = now
            return Transition(released: held, pressed: nil)
        }
        if magnitude < Motion.stickRelease {
            neutralSince = neutralSince ?? now
            isArmed = false
            return .none
        }
        if let since = neutralSince {
            isArmed = since.duration(to: now) >= Motion.stickRestDwell
            neutralSince = nil
        }
        guard isArmed, magnitude >= Motion.stickPress else { return .none }
        let direction = Self.direction(x: x, y: y)
        current = direction
        return Transition(released: nil, pressed: direction)
    }

    private static func direction(x: Float, y: Float) -> Direction {
        if abs(x) >= abs(y) {
            return x < 0 ? .left : .right
        }
        return y < 0 ? .down : .up
    }
}
