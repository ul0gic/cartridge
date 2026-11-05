struct ClipClock {
    static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    /// Every bundled core runs at the NTSC rate of about 60 Hz (the library imports US copies only).
    static let coreFrameNs = nanosecondsPerSecond / 60
    /// Segments close only once both tracks run past the boundary; 3 frames did in the pad probe, 12 leave margin.
    static let padFrames: UInt64 = 12

    private var offsetNs: UInt64?
    private var lastRealNs: UInt64?
    private var intervalNs: UInt64?
    private var resumePending = false
    private var lastNs: UInt64 = 0

    var lastFrameNs: UInt64? {
        lastRealNs
    }

    var contentEndNs: UInt64? {
        lastRealNs.map { $0 + interval }
    }

    private var interval: UInt64 {
        intervalNs ?? Self.coreFrameNs
    }

    mutating func time(forDisplay displayNs: UInt64) -> UInt64? {
        let time: UInt64
        if let offsetNs, !resumePending {
            guard displayNs > offsetNs, displayNs - offsetNs > lastNs else { return nil }
            time = displayNs - offsetNs
            if let lastRealNs {
                intervalNs = time - lastRealNs
            }
        } else {
            time = offsetNs == nil ? 0 : lastNs + interval
            guard displayNs >= time else { return nil }
            offsetNs = displayNs - time
            resumePending = false
        }
        lastNs = time
        lastRealNs = time
        return time
    }

    mutating func resume() {
        resumePending = offsetNs != nil
    }

    mutating func padTimes() -> [UInt64] {
        let boundary = (lastNs / Self.nanosecondsPerSecond + 1) * Self.nanosecondsPerSecond
        let times = (0..<Self.padFrames).map { boundary + $0 * Self.coreFrameNs }
        lastNs = times.last ?? lastNs
        return times
    }
}
