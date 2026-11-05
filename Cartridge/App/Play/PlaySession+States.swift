import Foundation

extension PlaySession {
    func enterRunning(began: ContinuousClock.Instant) async {
        let firstFrame = Self.milliseconds(since: began)
        if holdsFirstFrame {
            await setHostPaused(true)
            guard state == .starting else { return }
            isHeldAtFirstFrame = pausedAt != nil
            PlayLog.session.info("first-frame-held held=\(isHeldAtFirstFrame)")
        }
        state = .running
        PlayLog.session.info("first-frame ms=\(firstFrame)")
    }

    func releaseFirstFrame() async {
        guard isHeldAtFirstFrame else { return }
        isHeldAtFirstFrame = false
        await setHostPaused(false)
    }

    func setHostPaused(_ paused: Bool) async {
        let began = ContinuousClock.now
        do {
            try await connection?.setPaused(paused)
        } catch {
            PlayLog.session.error("set-paused-failed \(error.localizedDescription)")
            return
        }
        let milliseconds = Self.milliseconds(since: began)
        if paused {
            pausedAt = began
            PlayLog.session.info("pause ms=\(milliseconds)")
        } else {
            let pausedMs = pausedAt.map { String(Self.milliseconds(since: $0)) } ?? "unknown"
            pausedAt = nil
            PlayLog.session.info("resume ms=\(milliseconds) paused-ms=\(pausedMs)")
        }
    }

    func saveState(to url: URL) async throws {
        do {
            guard let connection else { throw CoreHostCallError.transport("no connection") }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await connection.saveState(toPath: url.path)
        } catch {
            PlayLog.session.error("state-save-failed \(error.localizedDescription)")
            throw PlayError.saveFailed(Self.saveFailure(from: error))
        }
    }

    func loadState(from url: URL) async throws {
        do {
            guard let connection else { throw CoreHostCallError.transport("no connection") }
            try await connection.loadState(fromPath: url.path)
        } catch {
            PlayLog.session.error("state-load-failed \(error.localizedDescription)")
            throw PlayError.loadFailed
        }
    }

    func writeSnapshot(to url: URL) -> Bool {
        guard let surfaces, let info = memory.readFrame() else { return false }
        return surfaces.writeSnapshot(of: info, to: url)
    }

    func setCheats(_ codes: [String]) async throws {
        let began = ContinuousClock.now
        guard let connection else { throw PlayError.helperUnavailable }
        do {
            try await connection.setCheats(codes)
        } catch let error as CoreHostCallError where error.hostCode == .cheatRejected {
            PlayLog.session.error(error.message)
            throw PlayError.cheatsRejected
        } catch {
            PlayLog.session.error("cheats-set-failed \(error.localizedDescription)")
            throw PlayError.helperUnavailable
        }
        PlayLog.session.info("cheats-applied count=\(codes.count) ms=\(Self.milliseconds(since: began))")
    }

    func batterySaveSize() async -> Int {
        guard let connection else { return 0 }
        do {
            return try await connection.batterySaveSize()
        } catch {
            PlayLog.session.error("battery-size-failed \(error.localizedDescription)")
            return 0
        }
    }

    func flushBatterySave() async throws -> Bool {
        do {
            guard let connection else { throw CoreHostCallError.transport("no connection") }
            return try await writeBattery(on: connection)
        } catch {
            PlayLog.session.error("battery-flush-failed \(error.localizedDescription)")
            throw PlayError.saveFailed(Self.saveFailure(from: error))
        }
    }

    func quitToLibrary() async throws -> QuitOutcome {
        switch state {
        case .running, .paused:
            break
        case .ended(let outcome):
            return outcome
        case .starting, .quitting, .failed, .crashed:
            return .withoutSaving
        }
        let began = ContinuousClock.now
        let wasRunning = state == .running
        state = .quitting
        let batteryWritten: Bool
        do {
            batteryWritten = try await writeQuitFiles()
        } catch {
            PlayLog.session.error("quit-save-failed \(error.localizedDescription)")
            if state == .crashed {
                throw PlayError.crashed
            }
            state = .paused
            if wasRunning {
                await setHostPaused(true)
            }
            throw PlayError.quitSaveFailed(Self.saveFailure(from: error))
        }
        writeResumeSnapshot()
        let now = Date.now
        playRecord.lastPlayedAt = now
        playRecord.resumeStateAt = now
        if batteryWritten {
            playRecord.batterySaveAt = now
        }
        addPlayedTime()
        await library.recordPlay(playRecord, for: game.id)
        await finishQuit(.saved, began: began)
        return .saved
    }

    func quitWithoutSaving() async {
        guard state == .running || state == .paused else { return }
        let began = ContinuousClock.now
        playRecord.lastPlayedAt = .now
        addPlayedTime()
        await library.recordPlay(playRecord, for: game.id)
        await finishQuit(.withoutSaving, began: began)
    }

    func trackPlayTime(leaving old: PlaySessionState) {
        if state == .running, old != .running {
            runningSince = .now
        } else if old == .running, state != .running, let since = runningSince {
            playedTime += since.duration(to: .now)
            runningSince = nil
        }
    }

    private func addPlayedTime() {
        let live = runningSince.map { $0.duration(to: .now) } ?? .zero
        playRecord.playSeconds = (playRecord.playSeconds ?? 0) + (playedTime + live).seconds
    }

    private func writeResumeSnapshot() {
        guard let surfaces, let info = memory.readFrame() else { return }
        let url = StoragePaths.resumeSnapshot(for: game.id)
        if surfaces.writeSnapshot(of: info, to: url) {
            PlayLog.session.info("resume-snapshot w=\(info.width) h=\(info.height)")
        } else {
            PlayLog.session.error("resume-snapshot-failed seq=\(info.sequence)")
        }
    }

    private func writeQuitFiles() async throws -> Bool {
        guard let connection else { throw CoreHostCallError.transport("no connection") }
        let written = try await writeBattery(on: connection)
        try await connection.saveState(toPath: StoragePaths.resumeState(for: game.id).path)
        PlayLog.session.info("resume-written")
        return written
    }

    private func writeBattery(on connection: CoreHostConnection) async throws -> Bool {
        try createSaveFolder()
        let written = try await connection.writeBatterySave()
        if written {
            let size = (try? FileManager.default.attributesOfItem(
                atPath: StoragePaths.batterySave(for: game.id).path
            )[.size] as? Int) ?? 0
            PlayLog.session.info("battery-written bytes=\(size)")
        }
        return written
    }

    private func finishQuit(_ outcome: QuitOutcome, began: ContinuousClock.Instant) async {
        await stopHost()
        unlinkSharedMemory()
        removeScratch()
        state = .ended(outcome)
        let name = outcome == .saved ? "saved" : "withoutSaving"
        PlayLog.session.info("quit outcome=\(name) ms=\(Self.milliseconds(since: began))")
        closeSessionLog(outcome: name)
    }

    private func createSaveFolder() throws {
        try FileManager.default.createDirectory(
            at: StoragePaths.saveFolder(for: game.id),
            withIntermediateDirectories: true
        )
    }

    private static func saveFailure(from error: any Error) -> SaveFailure {
        if let call = error as? CoreHostCallError, let code = call.hostCode {
            switch code {
            case .diskFull: return .diskFull
            case .serializeFailed: return .coreRefused
            default: return .writeFailed
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return .diskFull
        }
        return .writeFailed
    }
}
