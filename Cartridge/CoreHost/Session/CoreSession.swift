import Foundation
import IOSurface

struct StartRequest {
    let corePath: String
    let contentPath: String
    let systemDirectory: String
    let saveDirectory: String
    let batterySavePath: String
    let options: [String: String]
    let controllerPortDevice: UInt32
    let sharedMemoryName: String
    let frameSurfaces: [IOSurface]
}

struct StartedAVInfo {
    let baseWidth: Int32
    let baseHeight: Int32
    let maxWidth: Int32
    let maxHeight: Int32
    let aspectRatio: Double
    let fps: Double
    let sampleRate: Double

    init(_ av: retro_system_av_info) {
        baseWidth = Int32(clamping: av.geometry.base_width)
        baseHeight = Int32(clamping: av.geometry.base_height)
        maxWidth = Int32(clamping: av.geometry.max_width)
        maxHeight = Int32(clamping: av.geometry.max_height)
        aspectRatio = Double(av.geometry.aspect_ratio)
        fps = av.timing.fps
        sampleRate = av.timing.sample_rate
    }
}

private final class ContentBuffer {
    let pointer: UnsafeMutableRawPointer
    let count: Int

    init(path: String) throws(CoreHostFailure) {
        guard let size = try SessionFile.size(atPath: path, failureCode: .contentLoadFailed), size > 0 else {
            throw CoreHostFailure(code: .contentLoadFailed, message: "content file missing or empty")
        }
        guard size <= CoreSession.maxContentBytes else {
            throw CoreHostFailure(code: .contentLoadFailed, message: "content file \(size) bytes is too large")
        }
        pointer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        count = size
        do {
            try SessionFile.read(atPath: path, into: pointer, count: size, failureCode: .contentLoadFailed)
        } catch {
            pointer.deallocate()
            throw error
        }
    }

    deinit {
        pointer.deallocate()
    }
}

private struct AttachedCore {
    let library: CoreLibrary
    let callbacks: CoreCallbacks
    let info: CoreInfo
}

final class CoreSession {
    static let maxContentBytes = 256 << 20

    let stateStore: StateStore
    let battery: BatterySave
    let cheats: CheatList
    private let library: CoreLibrary
    private(set) var periodNs: UInt64
    private let callbacks: CoreCallbacks
    let shm: SharedMemoryMap
    private let audio: AudioOutput
    private let tap: AudioTapWriter?
    private let rewind: RewindHistory?
    private let content: ContentBuffer?

    private init(
        library: CoreLibrary,
        callbacks: CoreCallbacks,
        shm: SharedMemoryMap,
        audio: AudioOutput,
        tap: AudioTapWriter?,
        rewind: RewindHistory?,
        content: ContentBuffer?,
        periodNs: UInt64,
        battery: BatterySave,
        cheats: CheatList
    ) {
        self.library = library
        self.callbacks = callbacks
        self.shm = shm
        self.audio = audio
        self.tap = tap
        self.rewind = rewind
        self.content = content
        self.periodNs = periodNs
        self.battery = battery
        self.cheats = cheats
        stateStore = StateStore(library: library)
    }

    static func start(
        _ request: StartRequest,
        client: (any CoreHostClientProtocol)?
    ) throws(CoreHostFailure) -> (session: CoreSession, avInfo: StartedAVInfo) {
        var succeeded = false
        var undo: [() -> Void] = []
        defer {
            if !succeeded {
                undo.reversed().forEach { $0() }
            }
        }

        let shm = try SharedMemoryMap(name: request.sharedMemoryName)
        undo.append { shm.unmap() }
        let frameWriter = try FrameWriter(surfaces: request.frameSurfaces, shm: shm.pointer)
        try createSaveDirectory(request.saveDirectory)
        let core = try attachCore(
            request,
            client: client,
            frameWriter: frameWriter,
            shm: shm,
            undo: &undo
        )
        let library = core.library
        let callbacks = core.callbacks
        let content = try loadContent(request, core: core, undo: &undo)

        let av = library.systemAVInfo()
        let period = try framePeriod(of: av, frameWriter: frameWriter)
        let battery = BatterySave(library: library, path: request.batterySavePath)
        try battery.restore()
        library.setControllerPortDevice(port: 0, device: request.controllerPortDevice)

        let audio = try startAudio(request, sampleRate: av.timing.sample_rate, shm: shm, callbacks: callbacks)
        undo.append { audio.stop() }
        // The app unlinks the tap's name as soon as start replies, so it is opened here or never.
        let tap = AudioTapWriter(sharedMemoryName: request.sharedMemoryName, sampleRate: av.timing.sample_rate)
        callbacks.tap = tap
        undo.append { tap?.unmap() }
        let rewind = RewindProfile.forCore(at: request.corePath).flatMap {
            RewindHistory(library: library, environment: callbacks.environment, profile: $0)
        }

        let session = CoreSession(
            library: library,
            callbacks: callbacks,
            shm: shm,
            audio: audio,
            tap: tap,
            rewind: rewind,
            content: content,
            periodNs: period,
            battery: battery,
            cheats: CheatList(library: library, corePath: request.corePath)
        )
        succeeded = true
        return (session, StartedAVInfo(av))
    }

    private static func framePeriod(
        of av: retro_system_av_info,
        frameWriter: FrameWriter
    ) throws(CoreHostFailure) -> UInt64 {
        guard let period = FramePacing.periodNs(fps: av.timing.fps) else {
            throw CoreHostFailure(code: .coreLoadFailed, message: "core reported fps \(av.timing.fps)")
        }
        guard Int(av.geometry.max_width) <= frameWriter.width, Int(av.geometry.max_height) <= frameWriter.height else {
            throw CoreHostFailure(
                code: .surfacesUnavailable,
                message: "core maximum \(av.geometry.max_width)x\(av.geometry.max_height) exceeds the frame surfaces"
            )
        }
        return period
    }

    private static func startAudio(
        _ request: StartRequest,
        sampleRate: Double,
        shm: SharedMemoryMap,
        callbacks: CoreCallbacks
    ) throws(CoreHostFailure) -> AudioOutput {
        let audio = try AudioOutput(
            sampleRate: sampleRate,
            profile: AudioBufferProfile.forCore(at: request.corePath),
            shm: shm.pointer
        )
        callbacks.audio = audio
        try audio.start(atNs: FramePacing.nowNs())
        return audio
    }

    private static func createSaveDirectory(_ path: String) throws(CoreHostFailure) {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw CoreHostFailure(code: .writeFailed, message: "save directory: \(error.localizedDescription)")
        }
    }

    private static func attachCore(
        _ request: StartRequest,
        client: (any CoreHostClientProtocol)?,
        frameWriter: FrameWriter,
        shm: SharedMemoryMap,
        undo: inout [() -> Void]
    ) throws(CoreHostFailure) -> AttachedCore {
        let library = try CoreLibrary(path: request.corePath)
        guard let environment = Environment(
            systemDirectory: request.systemDirectory,
            saveDirectory: request.saveDirectory,
            options: CoreOptions.table(forCoreAt: request.corePath)
                .merging(request.options) { _, requested in requested },
            client: client
        ) else {
            throw CoreHostFailure(code: .coreLoadFailed, message: "environment allocation failed")
        }
        let callbacks = CoreCallbacks(
            environment: environment,
            frameWriter: frameWriter,
            input: InputSnapshot(shm: shm.pointer)
        )
        callbacks.installEnvironment(on: library)
        undo.append { callbacks.remove() }
        library.initialize()
        undo.append { library.deinitialize() }
        let info = library.systemInfo()
        CoreHostLog.core.info("valid extensions \(info.validExtensions)")
        callbacks.installRemaining(on: library)
        return AttachedCore(library: library, callbacks: callbacks, info: info)
    }

    private static func loadContent(
        _ request: StartRequest,
        core: AttachedCore,
        undo: inout [() -> Void]
    ) throws(CoreHostFailure) -> ContentBuffer? {
        let library = core.library
        let content = core.info.needFullpath ? nil : try ContentBuffer(path: request.contentPath)
        guard library.loadGame(path: request.contentPath, data: content?.pointer, size: content?.count ?? 0) else {
            throw CoreHostFailure(code: .contentLoadFailed, message: "retro_load_game returned false")
        }
        undo.append { library.unloadGame() }
        if let format = core.callbacks.environment.rejectedPixelFormat {
            throw CoreHostFailure(code: .contentLoadFailed, message: "core requires unsupported pixel format \(format)")
        }
        return content
    }

    func runFrame(startNs: UInt64, pacingInterval: UInt32, keepsSamples: Bool) {
        callbacks.keepsSamples = keepsSamples
        callbacks.frameWriter.beginFrame(startNs: startNs, pacingInterval: pacingInterval)
        library.run()
        if let sequence = callbacks.frameWriter.publishedSequence {
            tap?.tag(frameSequence: sequence)
        }
        if let period = callbacks.environment.takePendingFramePeriod() {
            periodNs = period
        }
        audio.tick(atNs: FramePacing.nowNs())
    }

    var audioLevel: AudioLevel {
        audio.level
    }

    func setPaused(_ paused: Bool) {
        cartridge_shm_set_paused(shm.pointer, paused ? 1 : 0)
    }

    func setAudioPaused(_ paused: Bool) {
        audio.setPaused(paused, atNs: FramePacing.nowNs())
    }

    var requestedSpeed: PlaySpeed {
        PlaySpeed(rawValue: cartridge_shm_read_speed_request(shm.pointer)) ?? .normal
    }

    func setActiveSpeed(_ speed: ActiveSpeed) {
        cartridge_shm_write_speed_active(shm.pointer, speed.rawValue)
        CoreHostLog.session.notice("speed mode=\(speed.logName)")
    }

    func captureRewindState() {
        rewind?.capture()
    }

    func stepBack() -> RewindStep {
        rewind?.stepBack() ?? .oldest
    }

    func rewindDidStart() {
        rewind?.rewindDidStart()
        rewind?.logHistory(periodNs: periodNs)
    }

    func rewindDidEnd() {
        rewind?.rewindDidEnd()
        rewind?.logHistory(periodNs: periodNs)
        reapplyCheats(after: .rewind)
    }

    func historyDidJump() {
        rewind?.clear()
    }

    func logRewindReport() {
        rewind?.logHistory(periodNs: periodNs)
        rewind?.logCaptureTiming()
    }

    func reset() {
        library.reset()
        reapplyCheats(after: .reset)
    }

    func loadState(fromPath path: String) throws(CoreHostFailure) {
        try stateStore.load(fromPath: path)
        reapplyCheats(after: .load)
    }

    func reapplyCheats(after event: CheatReapplyEvent) {
        guard !cheats.codes.isEmpty else { return }
        cheats.reapply()
        CoreHostLog.session.notice("cheats-reapplied after=\(event.rawValue) count=\(cheats.codes.count)")
    }

    func setDisc(index: Int) throws(CoreHostFailure) {
        try DiscControl(callbacks: callbacks.environment.diskControl).setDisc(index: index)
    }

    func stop() {
        audio.stop()
        library.unloadGame()
        library.deinitialize()
        callbacks.remove()
        tap?.unmap()
        shm.unmap()
    }
}
