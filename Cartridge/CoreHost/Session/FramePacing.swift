import Darwin

enum FreeReason: String {
    case noDisplay = "no-display"
    case stale
    case skew
}

enum PacingMode: Equatable {
    case locked(interval: UInt64)
    case free(FreeReason)
}

enum FramePacing {
    static let supportedFps: ClosedRange<Double> = 1...1000
    // RetroArch's default max_timing_skew (config.def.h:1469).
    static let maxTimingSkew = 0.05
    static let displayFreshnessNs: UInt64 = 100_000_000
    static let fastForwardRatio = 5.0

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nowNs() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    @inline(never)
    static func periodNs(fps: Double) -> UInt64? {
        guard supportedFps.contains(fps) else {
            return nil
        }
        return UInt64(1_000_000_000 / fps)
    }

    static func ticks(fromNs ns: UInt64) -> UInt32 {
        UInt32(clamping: ns * UInt64(timebase.denom) / UInt64(timebase.numer))
    }

    static func sleep(untilNs deadline: UInt64) {
        mach_wait_until(deadline * UInt64(timebase.denom) / UInt64(timebase.numer))
    }

    static func mode(corePeriodNs: UInt64, display: CartridgeDisplayTiming, nowNs: UInt64) -> PacingMode {
        guard display.periodNs > 0 else {
            return .free(.noDisplay)
        }
        guard nowNs <= display.tickNs || nowNs - display.tickNs <= displayFreshnessNs else {
            return .free(.stale)
        }
        // Swap interval and timing skew as RetroArch computes them (runloop.h:647-657).
        let interval = interval(corePeriodNs: corePeriodNs, displayPeriodNs: display.periodNs)
        let skew = skew(interval: interval, corePeriodNs: corePeriodNs, displayPeriodNs: display.periodNs)
        guard skew <= maxTimingSkew else {
            return .free(.skew)
        }
        return .locked(interval: interval)
    }

    private static func interval(corePeriodNs: UInt64, displayPeriodNs: UInt64) -> UInt64 {
        max(1, UInt64((Double(corePeriodNs) / Double(displayPeriodNs)).rounded()))
    }

    static func skew(interval: UInt64, corePeriodNs: UInt64, displayPeriodNs: UInt64) -> Double {
        abs(Double(interval) * Double(displayPeriodNs) - Double(corePeriodNs)) / Double(corePeriodNs)
    }

    static func lockedDeadline(after previousNs: UInt64, interval: UInt64, display: CartridgeDisplayTiming) -> UInt64 {
        let period = Int64(display.periodNs)
        let target = Int64(previousNs) + Int64(interval) * period
        let refreshes = (Double(target - Int64(display.tickNs)) / Double(period)).rounded()
        return UInt64(Int64(display.tickNs) + Int64(refreshes) * period)
    }

    static func fastForwardPeriodNs(corePeriodNs: UInt64) -> UInt64 {
        UInt64(Double(corePeriodNs) / fastForwardRatio)
    }

    /// RetroArch's anchor schedule (runloop.h:564-583): on time or late by under a period keeps the due time.
    static func nextAnchor(after anchorNs: UInt64, periodNs: UInt64, nowNs: UInt64) -> UInt64 {
        let due = anchorNs + periodNs
        return nowNs < due || nowNs - due < periodNs ? due : nowNs
    }

    static func nextSlot(after nowNs: UInt64, display: CartridgeDisplayTiming) -> UInt64 {
        let period = Int64(display.periodNs)
        let refreshes = (Double(Int64(nowNs) - Int64(display.tickNs)) / Double(period)).rounded(.down) + 1
        return UInt64(Int64(display.tickNs) + Int64(refreshes) * period)
    }
}
