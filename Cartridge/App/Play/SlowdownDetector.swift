struct SlowdownDetector {
    struct Recovery {
        let slowSeconds: Double
        let slowestFPS: Double
    }

    enum Event {
        case slowdown(seconds: Int)
        case recovered(Recovery)
    }

    private static let slowRatio = 0.9
    private static let slowSamples = 3

    private var samples = 0
    private var slowSinceNs: UInt64 = 0
    private var slowestFPS = 0.0

    mutating func record(fps: Double, targetFPS: Double, fromNs: UInt64) -> Event? {
        guard fps < targetFPS * Self.slowRatio else {
            defer { samples = 0 }
            guard samples >= Self.slowSamples else { return nil }
            let slowSeconds = Double(fromNs - slowSinceNs) / 1_000_000_000
            return .recovered(Recovery(slowSeconds: slowSeconds, slowestFPS: slowestFPS))
        }
        if samples == 0 {
            slowSinceNs = fromNs
            slowestFPS = fps
        }
        samples += 1
        slowestFPS = min(slowestFPS, fps)
        return samples == Self.slowSamples ? .slowdown(seconds: samples) : nil
    }
}
