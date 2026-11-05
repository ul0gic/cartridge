import Foundation

private enum Step {
    case wait
    case play
    case fastForward
    case rewind
}

final class CoreRunner {
    private static let threadName = "io.corelift.Cartridge.core"
    private static let stackBytes = 16 << 20
    private static let resyncThresholdNs: UInt64 = 1_000_000_000
    private static let frameReportIntervalNs: UInt64 = 10_000_000_000
    private static let policyRestoreIntervalNs: UInt64 = 1_000_000_000
    private static let pausedPollSeconds = 0.004

    private let condition = NSCondition()
    private var commands: [() -> Void] = []

    private(set) var session: CoreSession?
    private var activity: (any NSObjectProtocol)?
    private var startAttempted = false
    private var paused = false
    private var finished = false
    private var resetsDeadline = false
    private var deadlineNs: UInt64 = 0
    private var anchorNs: UInt64 = 0
    private var policyPeriodNs: UInt64 = 0
    private var lastPolicyRestoreNs: UInt64 = 0
    private var display = CartridgeDisplayTiming()
    private var pacing: PacingMode?
    private var step = Step.play
    private var audioPaused = false
    private var activeSpeed = ActiveSpeed.normal
    private var report = FrameTimingReport()

    init() {
        let thread = Thread { [self] in
            loop()
        }
        thread.name = Self.threadName
        thread.qualityOfService = .userInteractive
        thread.stackSize = Self.stackBytes
        thread.start()
    }

    func submit(_ command: @escaping () -> Void) {
        condition.lock()
        commands.append(command)
        condition.signal()
        condition.unlock()
    }

    func begin(
        _ request: StartRequest,
        client: (any CoreHostClientProtocol)?
    ) throws(CoreHostFailure) -> StartedAVInfo {
        guard !startAttempted else {
            throw CoreHostFailure(code: .alreadyStarted, message: "start was already called")
        }
        startAttempted = true
        openSessionLog(sharedMemoryName: request.sharedMemoryName, corePath: request.corePath)
        let started = try CoreSession.start(request, client: client)
        session = started.session
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Running game"
        )
        paused = false
        resetsDeadline = true
        logRole(event: "start")
        return started.avInfo
    }

    func requireSession() throws(CoreHostFailure) -> CoreSession {
        guard let session else {
            throw CoreHostFailure(code: .notStarted, message: "no session is running")
        }
        return session
    }

    func setPaused(_ paused: Bool) {
        guard let session, paused != self.paused else {
            return
        }
        self.paused = paused
        resetsDeadline = !paused
        session.setPaused(paused)
        if !paused {
            logRole(event: "resume")
        }
    }

    func showFrameIfPaused() {
        guard paused, let session else {
            return
        }
        session.runFrame(startNs: FramePacing.nowNs(), pacingInterval: 0, keepsSamples: false)
    }

    func shutdown() {
        session?.stop()
        session = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        finished = true
        CoreHostLog.session.notice("helper-stop pid=\(getpid())")
    }

    private func openSessionLog(sharedMemoryName: String, corePath: String) {
        guard let token = CartridgeSharedMemoryLayout.sessionToken(fromName: sharedMemoryName) else {
            CoreHostLog.session.error("session-log-unnamed")
            return
        }
        LogFile.shared.open(LogFile.sessionFile(token: token))
        let core = (corePath as NSString).lastPathComponent
        CoreHostLog.session.notice("helper-start pid=\(getpid()) core=\(core)")
    }

    private func loop() {
        while !finished {
            runQueuedCommands()
            guard !finished else {
                return
            }
            guard let session else {
                waitForCommands(until: nil)
                continue
            }
            let next = nextStep(session)
            if next != step {
                transition(from: step, to: next, session: session)
            }
            switch next {
            case .wait:
                waitForCommands(until: Date(timeIntervalSinceNow: Self.pausedPollSeconds))
            case .play, .rewind:
                lockedFrame(session)
            case .fastForward:
                fastForwardFrame(session)
            }
        }
    }

    private func lockedFrame(_ session: CoreSession) {
        let startNs = FramePacing.nowNs()
        if resetsDeadline {
            deadlineNs = startNs
            resetsDeadline = false
        }
        let mode = updatePacing(session: session, nowNs: startNs)
        let interval: UInt32 = switch mode {
        case .locked(let interval): UInt32(interval)
        case .free: 0
        }
        let ran = step == .rewind ? rewindFrame(session, interval: interval) : playFrame(session, interval: interval)
        pace(mode, corePeriodNs: session.periodNs)
        if ran {
            reportFrameTiming(session, periodNs: session.periodNs)
        }
    }

    private func pace(_ mode: PacingMode, corePeriodNs: UInt64) {
        let now = FramePacing.nowNs()
        switch mode {
        case .locked(let interval):
            deadlineNs = FramePacing.lockedDeadline(after: deadlineNs, interval: interval, display: display)
            if now >= deadlineNs {
                report.missed += 1
                // Waits for the next refresh as RetroArch blocks in nextDrawable (gfx/drivers/metal.m:2897-2902).
                deadlineNs = FramePacing.nextSlot(after: now, display: display)
            }
            FramePacing.sleep(untilNs: deadlineNs)
        case .free:
            deadlineNs += corePeriodNs
            if now < deadlineNs {
                FramePacing.sleep(untilNs: deadlineNs)
            } else {
                report.missed += 1
                if now - deadlineNs > Self.resyncThresholdNs {
                    deadlineNs = now
                }
            }
        }
    }

    @discardableResult
    private func run(_ session: CoreSession, restoresPolicy: Bool, frame: () -> Bool) -> Bool {
        let workStartNs = FramePacing.nowNs()
        let cpuStartNs = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        guard frame() else {
            return false
        }
        let workNs = FramePacing.nowNs() - workStartNs
        let cpuNs = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStartNs
        let schedule = RealTimePolicy.currentSchedule()
        if let schedule {
            cartridge_shm_write_core_schedule(session.shm.pointer, schedule)
            if restoresPolicy, schedule.policy == POLICY_TIMESHARE {
                restorePolicy(observed: schedule)
            }
        }
        report.record(workNs: workNs, cpuNs: cpuNs, schedule: schedule)
        return true
    }

    private func updatePacing(session: CoreSession, nowNs: UInt64) -> PacingMode {
        var latest = CartridgeDisplayTiming()
        if cartridge_shm_read_display(session.shm.pointer, &latest) {
            display = latest
        }
        let mode = FramePacing.mode(corePeriodNs: session.periodNs, display: display, nowNs: nowNs)
        if mode != pacing {
            pacing = mode
            switch mode {
            case .locked(let interval):
                logLocked(interval: interval, corePeriodNs: session.periodNs)
                applyPolicy(periodNs: interval * display.periodNs)
            case .free(let reason):
                CoreHostLog.session.notice("pacing free reason=\(reason.rawValue)")
            }
        }
        if case .free = mode, session.periodNs != policyPeriodNs {
            applyPolicy(periodNs: session.periodNs)
        }
        return mode
    }

    private func logLocked(interval: UInt64, corePeriodNs: UInt64) {
        let displayPeriodNs = display.periodNs
        let skew = FramePacing.skew(interval: interval, corePeriodNs: corePeriodNs, displayPeriodNs: displayPeriodNs)
        CoreHostLog.session.notice(
            """
            pacing locked n=\(interval) display-us=\(displayPeriodNs / 1000) \
            core-us=\(corePeriodNs / 1000) skew=\(String(format: "%.4f", skew))
            """
        )
    }

    private func applyPolicy(periodNs: UInt64) {
        policyPeriodNs = periodNs
        let result = RealTimePolicy.apply(periodNs: periodNs)
        if result == KERN_SUCCESS {
            CoreHostLog.session.notice("rt-policy period-us=\(periodNs / 1000)")
        } else {
            CoreHostLog.session.error("rt-policy failed kern_return=\(result)")
        }
    }

    private func restorePolicy(observed: CartridgeCoreSchedule) {
        let nowNs = FramePacing.nowNs()
        guard nowNs - lastPolicyRestoreNs >= Self.policyRestoreIntervalNs else {
            return
        }
        lastPolicyRestoreNs = nowNs
        let result = RealTimePolicy.apply(periodNs: policyPeriodNs)
        // A demoted thread keeps timeshare and only records the new mode (xnu osfmk/kern/priority.c:981-983).
        let after = RealTimePolicy.currentSchedule()
        let was = "was-policy=\(observed.policyName) was-curpri=\(observed.priority)"
        let now = "policy=\(after?.policyName ?? "unknown") curpri=\(after.map { String($0.priority) } ?? "unknown")"
        if result == KERN_SUCCESS, let after, after.policy != POLICY_TIMESHARE {
            CoreHostLog.session.notice("rt-restored \(was) \(now)")
        } else {
            CoreHostLog.session.error("rt-restore-failed kr=\(result) \(was) \(now)")
        }
        logRole(event: "restore")
    }

    private func logRole(event: String) {
        CoreHostLog.session.notice("helper-role event=\(event) \(RealTimePolicy.roleSummary())")
    }

    private func reportFrameTiming(_ session: CoreSession, periodNs: UInt64) {
        report.windowNs += periodNs
        guard report.windowNs >= Self.frameReportIntervalNs else {
            return
        }
        report.log(audio: session.audioLevel, residentBytes: Self.residentBytes())
        session.logRewindReport()
        report = FrameTimingReport()
    }

    private static func residentBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : nil
    }

    private func runQueuedCommands() {
        condition.lock()
        let pending = commands
        commands.removeAll()
        condition.unlock()
        pending.forEach { $0() }
    }

    private func waitForCommands(until deadline: Date?) {
        condition.lock()
        defer { condition.unlock() }
        while commands.isEmpty {
            if let deadline {
                guard condition.wait(until: deadline) else {
                    return
                }
            } else {
                condition.wait()
            }
        }
    }
}

extension CoreRunner {
    private func nextStep(_ session: CoreSession) -> Step {
        switch session.requestedSpeed {
        case .rewind: .rewind
        case .fastForward: paused ? .wait : .fastForward
        case .normal: paused ? .wait : .play
        }
    }

    private func transition(from previous: Step, to next: Step, session: CoreSession) {
        step = next
        switch previous {
        case .wait:
            resetsDeadline = true
        case .fastForward:
            // Re-entering the lock re-applies the time-constraint policy through updatePacing.
            resetsDeadline = true
            pacing = nil
        case .rewind:
            session.rewindDidEnd()
        case .play:
            break
        }
        switch next {
        case .fastForward:
            enterFastForward()
            setActive(.fastForward, session: session)
        case .rewind:
            session.rewindDidStart()
        case .wait, .play:
            setActive(.normal, session: session)
        }
        let holdsAudio = paused || next != .play
        if holdsAudio != audioPaused {
            audioPaused = holdsAudio
            session.setAudioPaused(holdsAudio)
        }
    }

    private func enterFastForward() {
        policyPeriodNs = 0
        let result = RealTimePolicy.applyStandard()
        if result == KERN_SUCCESS {
            CoreHostLog.session.notice("rt-policy standard")
        } else {
            CoreHostLog.session.error("rt-policy standard failed kern_return=\(result)")
        }
        anchorNs = FramePacing.nowNs()
    }

    private func setActive(_ speed: ActiveSpeed, session: CoreSession) {
        guard speed != activeSpeed else {
            return
        }
        activeSpeed = speed
        session.setActiveSpeed(speed)
    }

    private func playFrame(_ session: CoreSession, interval: UInt32) -> Bool {
        run(session, restoresPolicy: true) {
            session.captureRewindState()
            session.runFrame(startNs: deadlineNs, pacingInterval: interval, keepsSamples: true)
            return true
        }
    }

    private func rewindFrame(_ session: CoreSession, interval: UInt32) -> Bool {
        var outcome = RewindStep.between
        let ran = run(session, restoresPolicy: true) {
            outcome = session.stepBack()
            guard outcome == .stepped else {
                return false
            }
            session.runFrame(startNs: deadlineNs, pacingInterval: interval, keepsSamples: false)
            return true
        }
        switch outcome {
        case .stepped: setActive(.rewinding, session: session)
        case .oldest: setActive(.rewindHolding, session: session)
        case .between: break
        }
        return ran
    }

    private func fastForwardFrame(_ session: CoreSession) {
        let periodNs = FramePacing.fastForwardPeriodNs(corePeriodNs: session.periodNs)
        run(session, restoresPolicy: false) {
            session.captureRewindState()
            session.runFrame(startNs: anchorNs, pacingInterval: 0, keepsSamples: false)
            return true
        }
        let now = FramePacing.nowNs()
        anchorNs = FramePacing.nextAnchor(after: anchorNs, periodNs: periodNs, nowNs: now)
        if anchorNs > now {
            FramePacing.sleep(untilNs: anchorNs)
        }
        reportFrameTiming(session, periodNs: periodNs)
    }
}

private struct FrameTimingReport {
    var windowNs: UInt64 = 0
    var missed = 0
    private var frames: UInt64 = 0
    private var workNs: UInt64 = 0
    private var maxWorkNs: UInt64 = 0
    private var cpuNs: UInt64 = 0
    private var lowestPriority: Int32?
    private var lastSchedule: CartridgeCoreSchedule?
    private var timeshareFrames = 0
    private var unsampledFrames = 0

    mutating func record(workNs: UInt64, cpuNs: UInt64, schedule: CartridgeCoreSchedule?) {
        frames += 1
        self.workNs += workNs
        maxWorkNs = max(maxWorkNs, workNs)
        self.cpuNs += cpuNs
        guard let schedule else {
            unsampledFrames += 1
            return
        }
        lowestPriority = min(lowestPriority ?? schedule.priority, schedule.priority)
        lastSchedule = schedule
        if schedule.policy == POLICY_TIMESHARE {
            timeshareFrames += 1
        }
    }

    func log(audio: AudioLevel, residentBytes: UInt64?) {
        let curpri = lowestPriority.map(String.init) ?? "unknown"
        let policy = lastSchedule?.policyName ?? "unknown"
        let lastPriority = lastSchedule.map { String($0.priority) } ?? "unknown"
        let residentMB = residentBytes.map { String($0 >> 20) } ?? "unknown"
        CoreHostLog.session.notice(
            """
            frame-timing work-max-us=\(maxWorkNs / 1000) missed=\(missed) frames=\(frames) \
            work-avg-us=\(workNs / frames / 1000) cpu-avg-us=\(cpuNs / frames / 1000) curpri-min=\(curpri) \
            timeshare-frames=\(timeshareFrames) unsampled-frames=\(unsampledFrames) policy=\(policy) \
            curpri=\(lastPriority) audio-rate=\(audio.measuredRate) audio-fill-ms=\(audio.fillMs) \
            resident-mb=\(residentMB)
            """
        )
    }
}
