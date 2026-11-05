import AppKit
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class CartridgeInsert {
    enum Stage: Equatable {
        case inserting
        case holding(since: Date)
        case handingOver
        case ejecting(from: Double, at: Date, rate: Double)
    }

    enum EjectReason: String {
        case cancel
        case failed
        case ended
    }

    let game: GameID
    let setsUpXboxDrive: Bool
    let schedule: InsertSchedule
    let began = Date.now
    var stage = Stage.inserting
    @ObservationIgnored let startedAt = ContinuousClock.now
    @ObservationIgnored var sessionRunningAt: ContinuousClock.Instant?
    @ObservationIgnored var beats: Task<Void, Never>?

    init(game: GameID, system: GameSystem, setsUpXboxDrive: Bool) {
        self.game = game
        self.setsUpXboxDrive = setsUpXboxDrive
        schedule = system.insertSchedule
    }

    var isCancellable: Bool {
        switch stage {
        case .inserting, .holding: true
        case .handingOver, .ejecting: false
        }
    }

    var isEjecting: Bool {
        if case .ejecting = stage {
            true
        } else {
            false
        }
    }

    func milliseconds(at date: Date) -> Double {
        switch stage {
        case .inserting:
            min(schedule.totalAt, date.timeIntervalSince(began) * 1000)
        case .holding, .handingOver:
            schedule.totalAt
        // swiftlint:disable:next pattern_matching_keywords - swiftformat patternlet inline conflict
        case .ejecting(let from, let at, let rate):
            max(0, from - date.timeIntervalSince(at) * 1000 * rate)
        }
    }

    static func elapsed(from start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now).seconds * 1000)
    }
}

extension AppModel {
    func startPlay(_ game: GameRecord, withoutBIOS: Bool, start: SessionStart) {
        guard session == nil, insert == nil else { return }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            beginInsert(of: game)
        }
        launchSession(of: game, withoutBIOS: withoutBIOS, start: start, holdsFirstFrame: insert != nil)
        if !isPickingSlot {
            panelPhase = .starting
        }
    }

    func launchSession(of game: GameRecord, withoutBIOS: Bool, start: SessionStart, holdsFirstFrame: Bool = false) {
        let record = dependencies.library.playRecord(for: game.id)
        let session = dependencies.sessions.makeSession(
            for: game,
            playRecord: record,
            withoutBIOS: withoutBIOS,
            start: start,
            look: dependencies.looks.look(for: game.system)
        )
        session.holdsFirstFrame = holdsFirstFrame
        self.session = session
        sessionWithoutBIOS = withoutBIOS
        PlayLog.session.info("look system=\(game.system.rawValue) look=\(session.look.rawValue)")
        sessionWatcher = Task { [weak self] in
            for await state in Observations({ session.state }) {
                await self?.react(to: state, of: session)
            }
        }
        Task { await session.start() }
    }

    func cancelStart() {
        if let insert {
            guard insert.isCancellable else { return }
            ejectInsert(insert, reason: .cancel)
        }
        if let session, session.state == .running {
            Task { await session.quitWithoutSaving() }
        } else {
            session?.cancel()
        }
        panelPhase = .idle
    }

    func handlePlayEvent(_ event: NavigationEvent) {
        guard let session else { return }
        switch session.state {
        case .running:
            if event.action == .pause {
                requestPause(session)
            }
        case .paused:
            if let captureMenu {
                captureMenu.handle(event)
            } else {
                hub?.handle(event)
            }
        case .starting, .quitting, .ended, .failed, .crashed:
            break
        }
    }

    func hubDidAppear() {
        guard let pauseRequestedAt else { return }
        self.pauseRequestedAt = nil
        let milliseconds = Int(pauseRequestedAt.duration(to: .now).seconds * 1000)
        PlayLog.session.info("pause-shown ms=\(milliseconds)")
    }

    func libraryDidAppear() {
        guard let crashedAt else { return }
        self.crashedAt = nil
        let milliseconds = Int(crashedAt.duration(to: .now).seconds * 1000)
        PlayLog.session.info("crash-library-shown ms=\(milliseconds)")
    }

    func prepareToTerminate() async {
        UserDefaults.standard.set(fullScreenBeforePlay ?? isFullScreen, forKey: DefaultsKey.lastFullScreen.rawValue)
        guard let session else { return }
        await stopRecordingForQuit()
        do {
            _ = try await session.quitToLibrary()
        } catch {
            await session.quitWithoutSaving()
        }
    }

    func watchController() {
        let controller = dependencies.controller
        controllerWatcher = Task { [weak self] in
            for await connected in Observations({ controller.connected != nil }) {
                self?.controllerConnectionChanged(connected)
            }
        }
    }

    func watchActivation() {
        let center = NotificationCenter.default
        activationObservers = [
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pauseForBackground() }
            },
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeFromBackground() }
            },
        ]
    }

    private func pauseForBackground() {
        guard let session, route.isPlay, session.state == .running else { return }
        isPausedForBackground = true
        PlayLog.session.notice("background-pause")
        session.pause()
    }

    private func resumeFromBackground() {
        guard isPausedForBackground else { return }
        isPausedForBackground = false
        guard let session, session.state == .paused else { return }
        PlayLog.session.notice("background-resume")
        session.resume()
    }

    private func controllerConnectionChanged(_ connected: Bool) {
        guard let session else { return }
        if !connected, route.isPlay, session.state == .running {
            requestPause(session)
        } else if !connected, isPausedForBackground {
            isPausedForBackground = false
            PlayLog.session.notice("background-pause held reason=controller-disconnected")
            showPauseOverlay(session)
        }
        hub?.setControllerConnected(connected)
    }

    private func requestPause(_ session: any PlaySessionControlling) {
        pauseRequestedAt = .now
        session.pause()
    }

    private func react(to state: PlaySessionState, of session: any PlaySessionControlling) async {
        switch state {
        case .running:
            await sessionRunning(session)
        case .paused:
            dependencies.controller.playSink = nil
            dependencies.controller.mode = .navigation
            recorder?.setPaused(true)
            if !isPausedForBackground {
                showPauseOverlay(session)
            }
        case .ended:
            await finishSession(session, crashed: false)
        case .crashed:
            await finishSession(session, crashed: true)
        case .failed(let error):
            await sessionFailed(session, error: error)
        case .starting, .quitting:
            break
        }
    }

    private func sessionFailed(_ session: any PlaySessionControlling, error: PlayError) async {
        let wasPlaying = route.isPlay
        if let insert, !insert.isEjecting {
            ejectInsert(insert, reason: .failed)
        }
        panelPhase = .failed(error)
        dependencies.controller.playSink = nil
        sessionWatcher?.cancel()
        self.session = nil
        restart = nil
        await closeCapture(of: session)
        hub = nil
        guard wasPlaying else { return }
        dependencies.controller.mode = .navigation
        dependencies.environment.endPlay()
        fullScreenBeforePlay = nil
        show(.gamePanel(session.game.id))
    }

    private func showPauseOverlay(_ session: any PlaySessionControlling) {
        if isCapturePause {
            isCapturePause = false
            showCaptureMenu(session)
        } else {
            showHub(session)
        }
    }

    private func sessionRunning(_ session: any PlaySessionControlling) async {
        dependencies.controller.triggerRole = session.game.system.triggerRole
        dependencies.controller.faceLayout = session.game.system.faceLayout
        prepareSessionServices(for: session)
        recorder?.setPaused(false)
        if route.isPlay {
            hub = nil
            captureMenu = nil
            dependencies.controller.playSink = session.inputSink
            dependencies.controller.mode = .play
            logRestartIfNeeded()
            return
        }
        if let insert {
            await insertSessionRunning(session, insert: insert)
            return
        }
        withAnimation(Motion.easeInOut(Motion.handover)) {
            isFadingToBlack = true
        }
        try? await Task.sleep(for: Motion.handover)
        fullScreenBeforePlay = isFullScreen
        if let window {
            await dependencies.environment.beginPlay(in: window)
        }
        dependencies.controller.playSink = session.inputSink
        dependencies.controller.mode = .play
        show(.play(session.game.id))
        panelPhase = .idle
        isFadingToBlack = false
        showFirstPlayTips(for: session.game.system)
    }

    private func showFirstPlayTips(for system: GameSystem) {
        guard let playChips else { return }
        let defaults = UserDefaults.standard
        let guide = "Controller guide in Settings"
        if !defaults.bool(forKey: DefaultsKey.tipPlayBasicsSeen.rawValue) {
            defaults.set(true, forKey: DefaultsKey.tipPlayBasicsSeen.rawValue)
            playChips.tip(head: "Click the touchpad for the menu · Hold Create to capture", detail: guide)
        }
        if system.triggerRole == .speedControls, !defaults.bool(forKey: DefaultsKey.tipSpeedSeen.rawValue) {
            defaults.set(true, forKey: DefaultsKey.tipSpeedSeen.rawValue)
            playChips.tip(head: "Hold L2 to rewind · Hold R2 to fast forward", detail: guide)
        }
    }

    private func finishSession(_ session: any PlaySessionControlling, crashed: Bool) async {
        await closeCapture(of: session)
        let wasCancelled = !crashed && !route.isPlay
        if let insert {
            if !wasCancelled {
                insert.beats?.cancel()
                self.insert = nil
            } else if !insert.isEjecting {
                ejectInsert(insert, reason: .ended)
            }
        }
        dependencies.controller.playSink = nil
        dependencies.controller.mode = .navigation
        sessionWatcher?.cancel()
        self.session = nil
        hub = nil
        isPausedForBackground = false
        panelPhase = .idle
        isFadingToBlack = false
        guard !wasCancelled else { return }
        dependencies.environment.endPlay()
        fullScreenBeforePlay = nil
        if crashed {
            crashedGameTitle = session.game.title
            crashedAt = .now
        }
        cursor.focus(session.game, in: rows, preferringContinue: !crashed)
        shell.section = .home
        shell.barFocus = nil
        shell.home.focus(session.game.id, in: homeRows)
        show(.library)
    }

    private func beginInsert(of game: GameRecord) {
        let insert = CartridgeInsert(game: game.id, system: game.system, setsUpXboxDrive: setsUpXboxDrive(for: game))
        self.insert = insert
        PlayLog.session.info("insert-start system=\(game.system.rawValue)")
        insert.beats = Task { [weak self] in
            await self?.playInsertBeats(insert, system: game.system)
        }
    }

    private func playInsertBeats(_ insert: CartridgeInsert, system: GameSystem) async {
        let schedule = insert.schedule
        try? await Task.sleep(until: insert.startedAt + .milliseconds(schedule.soundAt), clock: .continuous)
        guard !Task.isCancelled else { return }
        UISound.play(system.isDisc ? .insertDisc : .insert)
        try? await Task.sleep(until: insert.startedAt + .milliseconds(schedule.seatedAt), clock: .continuous)
        guard !Task.isCancelled else { return }
        PlayLog.session.info("insert-seated ms=\(CartridgeInsert.elapsed(from: insert.startedAt))")
        try? await Task.sleep(until: insert.startedAt + .milliseconds(schedule.totalAt), clock: .continuous)
        guard !Task.isCancelled, self.insert === insert, insert.stage == .inserting else { return }
        if let session, let running = insert.sessionRunningAt {
            await handOver(session, insert: insert, waited: CartridgeInsert.elapsed(from: running), held: 0)
        } else {
            insert.stage = .holding(since: .now)
            PlayLog.session.info("insert-holding ms=\(CartridgeInsert.elapsed(from: insert.startedAt))")
        }
    }

    private func insertSessionRunning(_ session: any PlaySessionControlling, insert: CartridgeInsert) async {
        insert.sessionRunningAt = .now
        PlayLog.session.info("insert-session-running ms=\(CartridgeInsert.elapsed(from: insert.startedAt))")
        guard case .holding(let since) = insert.stage else { return }
        await handOver(session, insert: insert, waited: 0, held: Int(Date.now.timeIntervalSince(since) * 1000))
    }

    private func handOver(
        _ session: any PlaySessionControlling,
        insert: CartridgeInsert,
        waited: Int,
        held: Int
    ) async {
        insert.stage = .handingOver
        let total = CartridgeInsert.elapsed(from: insert.startedAt)
        PlayLog.session.info("handover waited-ms=\(waited) held-ms=\(held) total-ms=\(total)")
        await session.releaseFirstFrame()
        fullScreenBeforePlay = isFullScreen
        if let window {
            await dependencies.environment.beginPlay(in: window)
        }
        guard self.session === session, self.insert === insert, insert.stage == .handingOver else {
            dependencies.environment.endPlay()
            fullScreenBeforePlay = nil
            return
        }
        dependencies.controller.playSink = session.inputSink
        dependencies.controller.mode = .play
        show(.play(session.game.id))
        panelPhase = .idle
        self.insert = nil
        showFirstPlayTips(for: session.game.system)
    }

    private func ejectInsert(_ insert: CartridgeInsert, reason: CartridgeInsert.EjectReason) {
        let now = Date.now
        let from = insert.milliseconds(at: now)
        let rate = insert.schedule.ejectRate(from: from, failed: reason == .failed)
        insert.beats?.cancel()
        insert.stage = .ejecting(from: from, at: now, rate: rate)
        PlayLog.session.info("insert-eject reason=\(reason.rawValue) from-ms=\(Int(from)) span-ms=\(Int(from / rate))")
        insert.beats = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(from / rate))
            guard !Task.isCancelled, self?.insert === insert else { return }
            self?.insert = nil
        }
    }
}
