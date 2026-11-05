import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class PlaySession: PlaySessionControlling {
    private static let framePollInterval = Duration.milliseconds(5)

    let game: GameRecord
    var state = PlaySessionState.starting {
        didSet { trackPlayTime(leaving: oldValue) }
    }

    var geometry: FrameGeometry?
    var stats: PlayStats?
    var discIndex: Int
    var look: DisplayLook
    var captureSink: (any CaptureFrameSink)?
    private(set) var requestedSpeed = PlaySpeed.normal

    @ObservationIgnored let token = String(UUID().uuidString.replacing("-", with: "").lowercased().prefix(8))
    @ObservationIgnored let createdAt = ContinuousClock.now
    @ObservationIgnored let library: any LibraryStoring
    @ObservationIgnored let memory: SessionSharedMemory
    @ObservationIgnored let audioTap: SessionAudioTap?
    @ObservationIgnored let start: SessionStart
    @ObservationIgnored let statsLogger: StatsLogger
    @ObservationIgnored var playRecord: PlayRecord
    @ObservationIgnored var connection: CoreHostConnection?
    @ObservationIgnored var isStopping = false
    @ObservationIgnored let surfaces: FrameSurfaces?
    @ObservationIgnored private let withoutBIOS: Bool
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored var pausedAt: ContinuousClock.Instant?
    @ObservationIgnored var runningSince: ContinuousClock.Instant?
    @ObservationIgnored var playedTime = Duration.zero
    @ObservationIgnored var sessionLogOpen = false
    @ObservationIgnored var holdsFirstFrame = false
    @ObservationIgnored var isHeldAtFirstFrame = false

    init(
        game: GameRecord,
        playRecord: PlayRecord?,
        withoutBIOS: Bool,
        start: SessionStart,
        look: DisplayLook,
        library: any LibraryStoring
    ) {
        let record = playRecord ?? PlayRecord(
            lastPlayedAt: nil,
            resumeStateAt: nil,
            manualStateAt: nil,
            batterySaveAt: nil,
            discIndex: 0
        )
        self.game = game
        self.library = library
        self.withoutBIOS = withoutBIOS
        self.start = start
        self.look = look
        self.playRecord = record
        discIndex = record.discIndex
        surfaces = FrameSurfaces(size: game.system.frameSurfaceSize)
        memory = SessionSharedMemory(token: token)
        let tap = SessionAudioTap(token: token)
        audioTap = tap.isMapped ? tap : nil
        statsLogger = StatsLogger(memory: memory, targetFPS: 0) { _ in }
        statsLogger.onSample = { [weak self] stats in
            self?.stats = stats
        }
    }

    func start() async {
        guard state == .starting, connection == nil else { return }
        let began = ContinuousClock.now
        let title = game.title
        let system = game.system.rawValue
        openSessionLog()
        PlayLog.session.info("start mode=\(start.logName) game=\"\(title)\" system=\(system)")
        if withoutBIOS {
            PlayLog.session.info("bios-skipped")
        }
        let startBudget = game.system.startBudget
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: startBudget)
            guard !Task.isCancelled else { return }
            self?.startTimedOut()
        }
        do {
            let request = try await makeRequest()
            guard state == .starting else {
                removeScratch()
                return
            }
            try await launch(request, began: began)
        } catch let error as PlayError {
            fail(error)
        } catch let error as CoreHostCallError {
            if state == .starting {
                PlayLog.session.error("start-failed \(error.message)")
            }
            fail(error.startFailure(for: game.system))
        } catch is CancellationError {
            fail(.helperUnavailable)
        } catch {
            if state == .starting {
                PlayLog.session.error("start-failed \(error.localizedDescription)")
            }
            fail(.helperUnavailable)
        }
    }

    func cancel() {
        guard state == .starting else { return }
        teardown()
        state = .ended(.withoutSaving)
        PlayLog.session.info("cancel")
        closeSessionLog(outcome: "cancelled")
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        Task { await setHostPaused(true) }
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        Task { await setHostPaused(false) }
    }

    func stopHost() async {
        isStopping = true
        eventsTask?.cancel()
        do {
            try await connection?.stop()
        } catch {
            PlayLog.session.debug("stop-ended \(error.localizedDescription)")
        }
        connection?.invalidate()
        connection = nil
    }

    func removeScratch() {
        let folder = StoragePaths.scratchFolder(for: token)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            PlayLog.session.error("scratch-remove-failed \(error.localizedDescription)")
        }
    }

    static func milliseconds(since instant: ContinuousClock.Instant) -> Int {
        let elapsed = instant.duration(to: .now)
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private func makeRequest() async throws -> StartRequest {
        guard memory.isMapped, let surfaces else {
            throw PlayError.helperUnavailable
        }
        guard let corePath = game.system.coreLibraryURL, FileManager.default.fileExists(atPath: corePath.path) else {
            throw PlayError.coreMissing(game.system)
        }
        let saveFolder = StoragePaths.saveFolder(for: game.id)
        do {
            try FileManager.default.createDirectory(at: StoragePaths.system, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        } catch {
            PlayLog.session.error("directory-create-failed \(error.localizedDescription)")
            throw PlayError.contentUnreadable
        }
        return try await StartRequest(
            corePath: corePath.path,
            contentPath: contentPath(),
            systemDirectory: StoragePaths.system.path,
            saveDirectory: saveFolder.path,
            batterySavePath: StoragePaths.batterySave(for: game.id).path,
            controllerPortDevice: game.system == .ps1 ? .psDualShock : .joypad,
            options: xboxStartOptions(),
            sharedMemoryName: memory.name,
            frameSurfaces: surfaces.surfaces
        )
    }

    private func contentPath() async throws -> String {
        switch game.kind {
        case .file, .multiDisc:
            return game.fileURL.path
        case .disc(let cuePath):
            return cuePath
        case .zipped:
            let archive = game.fileURL
            let directory = StoragePaths.scratchFolder(for: token)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                return try await Task.detached {
                    guard let entry = try ZipArchive.inspect(archive) else { throw PlayError.contentUnreadable }
                    return try ZipArchive.extract(entry, from: archive, to: directory).path
                }.value
            } catch let error as PlayError {
                throw error
            } catch {
                PlayLog.session.error("extract-failed \(error.localizedDescription)")
                throw PlayError.contentUnreadable
            }
        }
    }

    private func launch(_ request: StartRequest, began: ContinuousClock.Instant) async throws {
        let connection = CoreHostConnection(
            serviceName: game.system.helperServiceName,
            onGeometry: { [weak self] width, height, aspectRatio in
                Task { @MainActor in
                    self?.geometryDidChange(width: Int(width), height: Int(height), aspect: aspectRatio)
                }
            },
            onAVInfo: { [weak self] _, _, fps, _ in
                Task { @MainActor in self?.statsLogger.targetFPS = fps }
            }
        )
        self.connection = connection
        eventsTask = Task { [weak self] in
            for await event in connection.events {
                self?.handle(event)
            }
        }

        let reply = try await connection.start(request)
        unlinkSharedMemory()
        guard state == .starting else { return }
        statsLogger.targetFPS = reply.fps
        guard geometryDidChange(width: reply.baseWidth, height: reply.baseHeight, aspect: reply.aspectRatio) else {
            throw PlayError.helperUnavailable
        }
        await restoreResume(on: connection)
        try await restoreSlot(on: connection)
        await restoreDisc(on: connection)

        while state == .starting {
            if let frame = memory.readFrame(), frame.sequence > 0 {
                break
            }
            try await Task.sleep(for: Self.framePollInterval)
        }
        guard state == .starting else { return }
        watchdog?.cancel()
        await enterRunning(began: began)
    }

    @discardableResult
    private func geometryDidChange(width: Int, height: Int, aspect: Double) -> Bool {
        let aspectRatio = aspect > 0 ? aspect : (height > 0 ? Double(width) / Double(height) : 0)
        guard width > 0, height > 0, aspectRatio > 0 else {
            PlayLog.session.error("geometry-invalid w=\(width) h=\(height) aspect=\(aspect)")
            return false
        }
        geometry = FrameGeometry(width: width, height: height, aspectRatio: aspectRatio)
        PlayLog.session.info("geometry w=\(width) h=\(height) aspect=\(String(format: "%.4f", aspectRatio))")
        return true
    }

    private func handle(_ event: ConnectionEvent) {
        guard !isStopping else { return }
        switch state {
        case .starting:
            fail(.helperUnavailable)
        case .running, .paused, .quitting:
            crash()
        case .ended, .failed, .crashed:
            break
        }
    }

    private func startTimedOut() {
        guard state == .starting else { return }
        fail(.startTimeout)
    }

    private func crash() {
        let title = game.title
        PlayLog.session.error("crash game=\"\(title)\"")
        state = .crashed
        teardown()
        closeSessionLog(outcome: "crashed")
    }

    private func fail(_ error: PlayError) {
        guard state == .starting else { return }
        PlayLog.session.error("failed reason=\(error.logName)")
        state = .failed(error)
        teardown()
        closeSessionLog(outcome: "failed")
    }

    private func teardown() {
        watchdog?.cancel()
        eventsTask?.cancel()
        connection?.invalidate()
        connection = nil
        unlinkSharedMemory()
        removeScratch()
    }
}

extension PlaySession {
    private func restoreResume(on connection: CoreHostConnection) async {
        guard state == .starting, start == .resume, playRecord.resumeStateAt != nil else { return }
        do {
            try await connection.loadState(fromPath: StoragePaths.resumeState(for: game.id).path)
            PlayLog.session.info("resume-loaded")
        } catch {
            guard state == .starting else { return }
            PlayLog.session.error("resume-load-failed \(error.localizedDescription)")
        }
    }

    private func restoreSlot(on connection: CoreHostConnection) async throws {
        guard state == .starting, case .slot(let slot) = start else { return }
        do {
            try await connection.loadState(fromPath: StoragePaths.slotState(slot, for: game.id).path)
            PlayLog.session.info("slot-loaded n=\(slot.value)")
        } catch {
            guard state == .starting else { return }
            PlayLog.session.error("slot-load-failed n=\(slot.value) \(error.localizedDescription)")
            throw PlayError.loadFailed
        }
    }

    private func restoreDisc(on connection: CoreHostConnection) async {
        guard state == .starting, discIndex > 0, discIndex < discCount else { return }
        do {
            try await connection.setDisc(index: discIndex)
        } catch {
            guard state == .starting else { return }
            PlayLog.session.error("initial-disc-failed \(error.localizedDescription)")
            discIndex = 0
        }
    }
}

extension PlaySession {
    var discCount: Int {
        guard case .multiDisc(let cuePaths, _) = game.kind else { return 1 }
        return cuePaths.count
    }

    var activeSpeed: ActiveSpeed? {
        memory.readActiveSpeed()
    }

    var inputSink: any PlayInputSink {
        memory
    }

    var frameView: AnyView {
        guard let surfaces else { return AnyView(Color.black) }
        return AnyView(GameFrameView(
            surfaces: surfaces,
            memory: memory,
            stats: statsLogger,
            geometry: geometry,
            look: look,
            captureSink: captureSink
        ))
    }

    func setSpeed(_ speed: PlaySpeed) {
        memory.setSpeed(speed)
        requestedSpeed = speed
        PlayLog.session.info("speed-requested speed=\(speed.logName)")
    }

    func unlinkSharedMemory() {
        memory.unlink()
        audioTap?.unlink()
    }
}

extension PlayError {
    fileprivate var logName: String {
        switch self {
        case .coreMissing: "coreMissing"
        case .contentUnreadable: "contentUnreadable"
        case .helperUnavailable: "helperUnavailable"
        case .startTimeout: "startTimeout"
        case .crashed: "crashed"
        case .saveFailed: "saveFailed"
        case .loadFailed: "loadFailed"
        case .quitSaveFailed: "quitSaveFailed"
        case .discChangeFailed: "discChangeFailed"
        case .cheatsRejected: "cheatsRejected"
        }
    }
}

extension SessionStart {
    fileprivate var logName: String {
        switch self {
        case .resume: "resume"
        case .fresh: "fresh"
        case .slot(let slot): slot.fileStem
        }
    }
}

extension PlaySpeed {
    fileprivate var logName: String {
        switch self {
        case .normal: "normal"
        case .rewind: "rewind"
        case .fastForward: "fast-forward"
        }
    }
}
