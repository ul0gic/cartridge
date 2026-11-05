import Foundation

@MainActor
final class StatsLogger {
    private struct Sample {
        let nanoseconds: UInt64
        let produced: UInt64
        let published: UInt64
        let presented: UInt64
        let underruns: UInt64
        let excess: UInt64
        let longHolds: UInt64
    }

    private struct Presentation {
        let displayNs: UInt64
        let pacingInterval: UInt32
    }

    private struct LatencyWindow {
        var samples = 0
        var lockedFrames = 0
        var minRefreshes: UInt64?
        var maxRefreshes: UInt64?
        var longHolds = 0

        mutating func record(refreshes: UInt64) {
            lockedFrames += 1
            minRefreshes = min(minRefreshes ?? refreshes, refreshes)
            maxRefreshes = max(maxRefreshes ?? refreshes, refreshes)
        }
    }

    private static let intervalNanoseconds: UInt64 = 1_000_000_000
    private static let latencyReportSamples = 10

    var targetFPS: Double
    private let memory: SessionSharedMemory
    var onSample: (PlayStats) -> Void
    private var presented: UInt64 = 0
    private var longHolds: UInt64 = 0
    private var lastPresentation: Presentation?
    private var latency = LatencyWindow()
    private var previous: Sample?
    private var slowdown = SlowdownDetector()
    private var lastRefreshNs: UInt64 = 0

    init(memory: SessionSharedMemory, targetFPS: Double, onSample: @escaping (PlayStats) -> Void) {
        self.memory = memory
        self.targetFPS = targetFPS
        self.onSample = onSample
    }

    func didPresent(_ frame: CartridgeFrame, displayNs: UInt64, refreshNs: UInt64) {
        presented += 1
        lastRefreshNs = refreshNs
        defer { lastPresentation = Presentation(displayNs: displayNs, pacingInterval: frame.pacingInterval) }
        guard refreshNs > 0 else { return }
        if frame.pacingInterval > 0, displayNs > frame.startNs {
            latency.record(refreshes: Self.refreshes(displayNs - frame.startNs, refreshNs: refreshNs))
        }
        guard let last = lastPresentation, last.pacingInterval > 0, displayNs > last.displayNs else { return }
        if Self.refreshes(displayNs - last.displayNs, refreshNs: refreshNs) > UInt64(last.pacingInterval) {
            longHolds += 1
        }
    }

    private static func refreshes(_ nanoseconds: UInt64, refreshNs: UInt64) -> UInt64 {
        UInt64((Double(nanoseconds) / Double(refreshNs)).rounded())
    }

    func sampleIfDue() {
        guard let counters = memory.readCounters(), let frame = memory.readFrame() else { return }
        if counters.paused != 0 {
            lastPresentation = nil
        }
        let now = DispatchTime.now().uptimeNanoseconds
        let current = Sample(
            nanoseconds: now,
            produced: counters.framesProduced,
            published: frame.sequence,
            presented: presented,
            underruns: counters.audioUnderruns,
            excess: frame.sequence > presented + 1 ? frame.sequence - presented - 1 : 0,
            longHolds: longHolds
        )
        guard let previous else {
            previous = current
            return
        }
        guard now - previous.nanoseconds >= Self.intervalNanoseconds else { return }
        self.previous = current

        let interval = Double(now - previous.nanoseconds) / 1_000_000_000
        let stats = PlayStats(
            targetFPS: targetFPS,
            producedLastSecond: Int(current.produced - previous.produced),
            presentedLastSecond: Int(current.presented - previous.presented),
            droppedLastSecond: Int(current.excess) - Int(previous.excess),
            underrunsLastSecond: Int(current.underruns - previous.underruns),
            longHoldsLastSecond: Int(current.longHolds - previous.longHolds),
            intervalSeconds: interval
        )
        let fps = Double(stats.producedLastSecond) / interval
        let disrupted = stats.droppedLastSecond > 0 || stats.underrunsLastSecond > 0 || stats.longHoldsLastSecond > 0
        PlayLog.stats.log(
            level: disrupted ? .notice : .info,
            """
            fps=\(String(format: "%.2f", fps)) target=\(String(format: "%.2f", stats.targetFPS)) \
            presented=\(stats.presentedLastSecond) dropped=\(stats.droppedLastSecond) \
            underruns=\(stats.underrunsLastSecond) long-holds=\(stats.longHoldsLastSecond) paused=\(counters.paused) \
            speed=\(memory.readActiveSpeed()?.logName ?? "unknown")
            """
        )
        reportLatency(longHolds: stats.longHoldsLastSecond)
        if counters.paused == 0, targetFPS > 0 {
            reportSlowdown(fps: fps, fromNs: previous.nanoseconds)
        }
        onSample(stats)
    }

    private func reportSlowdown(fps: Double, fromNs: UInt64) {
        guard let event = slowdown.record(fps: fps, targetFPS: targetFPS, fromNs: fromNs) else { return }
        let schedule = memory.readCoreSchedule()
        let core = "core-policy=\(schedule?.policyName ?? "unknown") core-priority=\(schedule.map { String($0.priority) } ?? "unknown")"
        let rates = "fps=\(String(format: "%.2f", fps)) target=\(String(format: "%.2f", targetFPS))"
        switch event {
        case .slowdown(let seconds):
            let displayHz = lastRefreshNs > 0 ? String(1_000_000_000 / lastRefreshNs) : "unknown"
            PlayLog.stats.notice(
                """
                slowdown \(rates) seconds=\(seconds) \(core) display-hz=\(displayHz) \
                \(SystemConditions.power) \(SystemConditions.focus)
                """
            )
        case .recovered(let recovery):
            PlayLog.stats.notice(
                """
                recovered \(rates) slow-s=\(String(format: "%.1f", recovery.slowSeconds)) \
                slowest-fps=\(String(format: "%.2f", recovery.slowestFPS)) \(core) \(SystemConditions.power)
                """
            )
        }
    }

    private func reportLatency(longHolds: Int) {
        latency.samples += 1
        latency.longHolds += longHolds
        guard latency.samples >= Self.latencyReportSamples else { return }
        let window = latency
        latency = LatencyWindow()
        let minimum = window.minRefreshes.map(String.init) ?? "none"
        let maximum = window.maxRefreshes.map(String.init) ?? "none"
        PlayLog.stats.notice(
            """
            present-timing locked-frames=\(window.lockedFrames) latency-refreshes-min=\(minimum) \
            latency-refreshes-max=\(maximum) long-holds=\(window.longHolds)
            """
        )
    }
}
