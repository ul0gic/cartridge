import AppKit

extension AppModel {
    func handlePlayControl(_ event: PlayControlEvent) {
        switch event {
        case .rewindHeld(let held):
            hub?.rewindHeld(held)
        case .captureRequested:
            guard route.isPlay, let session, session.state == .running, recorder != nil else { return }
            isCapturePause = true
            session.pause()
        }
    }

    func showHub(_ session: any PlaySessionControlling) {
        guard hub == nil, let sessionCheats else { return }
        hub = HubModel(
            session: session,
            dependencies: dependencies,
            cheats: sessionCheats,
            isControllerConnected: dependencies.controller.connected != nil,
            hooks: HubHooks(
                stopRecording: { [weak self] in await self?.stopRecordingForQuit() },
                restart: { [weak self] in self?.restartSession(reason: $0) },
                chooseSaveFile: { [weak self] in await self?.chooseSaveFile(message: $0) }
            )
        )
    }

    func showCaptureMenu(_ session: any PlaySessionControlling) {
        guard captureMenu == nil, let recorder, let playChips else { return }
        captureMenu = CaptureMenuModel(recorder: recorder, chips: playChips) { [weak session] in
            session?.resume()
        }
    }

    func prepareSessionServices(for session: any PlaySessionControlling) {
        guard recorder == nil else { return }
        let recorder = CaptureRecorder(game: session.game, tap: session.audioTap, gallery: dependencies.gallery)
        let chips = PlayChipsModel(recorder: recorder, session: session)
        recorder.onRecordingEnded = { [weak chips] in chips?.recordingEnded($0) }
        session.captureSink = recorder
        self.recorder = recorder
        playChips = chips
        let cheats = SessionCheats(
            game: session.game,
            database: dependencies.cheats,
            store: dependencies.cheatSettings
        )
        sessionCheats = cheats
        Task { await applyStoredCheats(cheats, to: session) }
    }

    func closeCapture(of session: any PlaySessionControlling) async {
        let recorder = recorder
        self.recorder = nil
        playChips?.stop()
        playChips = nil
        captureMenu = nil
        sessionCheats = nil
        session.captureSink = nil
        await recorder?.close()
    }

    func stopRecordingForQuit() async {
        guard let recorder, recorder.isRecording else { return }
        do {
            _ = try await recorder.stopRecording()
        } catch {
            PlayLog.session.error("recording-stop-at-quit-failed")
        }
    }

    func restartSession(reason: RestartReason) {
        guard let old = session, route.isPlay else { return }
        restart = (reason, .now)
        sessionWatcher?.cancel()
        dependencies.controller.playSink = nil
        dependencies.controller.mode = .navigation
        let game = old.game
        let withoutBIOS = sessionWithoutBIOS
        Task {
            await closeCapture(of: old)
            await old.quitWithoutSaving()
            launchSession(of: game, withoutBIOS: withoutBIOS, start: .fresh)
        }
    }

    func logRestartIfNeeded() {
        guard let restart else { return }
        self.restart = nil
        PlayLog.session.info(
            "restart-fresh reason=\(restart.reason.logName) ms=\(HubFormat.milliseconds(since: restart.began))"
        )
    }

    func chooseSaveFile(message: String) async -> URL? {
        isPickerOpen = true
        defer { isPickerOpen = false }
        return await SaveFilePicker.choose(message: message)
    }

    private func applyStoredCheats(_ cheats: SessionCheats, to session: any PlaySessionControlling) async {
        let settings = cheats.settings
        guard await !cheats.codes(for: settings, in: cheats.lookup).isEmpty else { return }
        do {
            try await cheats.apply(settings, to: session)
        } catch {
            PlayLog.session.error("cheats-startup-failed")
        }
    }
}

enum SaveFilePicker {
    @MainActor
    static func choose(message: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = message
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
