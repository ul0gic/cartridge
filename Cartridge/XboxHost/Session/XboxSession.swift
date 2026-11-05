import Foundation
import IOSurface

struct XboxStartRequest {
    let corePath: String
    let contentPath: String
    let saveDirectory: String
    let options: [String: String]
    let sharedMemoryName: String
    let frameSurfaces: [IOSurface]
}

private struct XboxOptions {
    let bootROMPath: String
    let flashPath: String
    let eepromPath: String
    let baseDrivePath: String
    let gameDrivePath: String
    let configDirectory: String
    let boot: XboxBootMode

    init(_ options: [String: String]) throws(XboxHostFailure) {
        bootROMPath = try Self.path(.bootROMPath, in: options)
        flashPath = try Self.path(.flashPath, in: options)
        eepromPath = try Self.path(.eepromPath, in: options)
        baseDrivePath = try Self.path(.baseDrivePath, in: options)
        gameDrivePath = try Self.path(.gameDrivePath, in: options)
        configDirectory = try Self.path(.configDirectory, in: options)
        let bootValue = try Self.value(.boot, in: options)
        guard let boot = XboxBootMode(rawValue: bootValue) else {
            throw XboxHostFailure(
                code: .contentLoadFailed,
                message: "start option \(XboxStartOption.boot.rawValue) is \(bootValue)"
            )
        }
        self.boot = boot
    }

    private static func value(_ key: XboxStartOption, in options: [String: String]) throws(XboxHostFailure) -> String {
        guard let value = options[key.rawValue] else {
            throw XboxHostFailure(code: .contentLoadFailed, message: "start option \(key.rawValue) missing")
        }
        return value
    }

    private static func path(_ key: XboxStartOption, in options: [String: String]) throws(XboxHostFailure) -> String {
        let value = try value(key, in: options)
        guard value.hasPrefix("/") else {
            throw XboxHostFailure(
                code: .contentLoadFailed,
                message: "start option \(key.rawValue) is not an absolute path"
            )
        }
        return value
    }
}

private final class XboxCallbacks {
    let frames: XboxFrames
    let pad: XboxPad
    let audio: XboxAudio
    let guestStopped: () -> Void

    init(frames: XboxFrames, pad: XboxPad, audio: XboxAudio, guestStopped: @escaping () -> Void) {
        self.frames = frames
        self.pad = pad
        self.audio = audio
        self.guestStopped = guestStopped
    }

    static func from(_ context: UnsafeMutableRawPointer?) -> XboxCallbacks? {
        context.map { Unmanaged<XboxCallbacks>.fromOpaque($0).takeUnretainedValue() }
    }

    func host() -> CartridgeXemuHost {
        var host = CartridgeXemuHost()
        // The library calls back with this pointer until the process exits, so the reference is never released.
        host.context = Unmanaged.passRetained(self).toOpaque()
        host.frame_ready = { context, surface, width, height in
            XboxCallbacks.from(context)?.frames.publish(surface: surface, width: width, height: height)
        }
        host.read_pad = { context, pad in
            guard let pad else { return }
            XboxCallbacks.from(context)?.pad.read(into: pad)
        }
        host.audio = { context, frames, count in
            guard let frames else { return }
            XboxCallbacks.from(context)?.audio.write(frames, count: count)
        }
        host.audio_underrun = { context in
            XboxCallbacks.from(context)?.audio.underrun()
        }
        host.log = { _, level, message in
            guard let message else { return }
            XboxHostLog.recordCoreLine(level: level, message: message)
        }
        host.guest_stopped = { context in
            XboxCallbacks.from(context)?.guestStopped()
        }
        return host
    }
}

final class XboxSession {
    static let renderScale: UInt32 = 1
    static let baseWidth: Int32 = 640
    static let baseHeight: Int32 = 480
    static let fps = 60.0

    let library: XemuLibrary
    let saveDirectory: URL
    let gameDrivePath: String
    var awaitingRestore: Bool
    private(set) var paused = false
    private var stopped = false
    private let shm: UnsafeMutablePointer<CartridgeSharedMemory>
    private let tap: UnsafeMutablePointer<CartridgeAudioTap>?

    private init(
        library: XemuLibrary,
        request: XboxStartRequest,
        options: XboxOptions,
        shm: UnsafeMutablePointer<CartridgeSharedMemory>,
        tap: UnsafeMutablePointer<CartridgeAudioTap>?
    ) {
        self.library = library
        saveDirectory = URL(filePath: request.saveDirectory, directoryHint: .isDirectory)
        gameDrivePath = options.gameDrivePath
        awaitingRestore = options.boot == .restore
        self.shm = shm
        self.tap = tap
    }

    static func start(
        _ request: XboxStartRequest,
        client: (any CoreHostClientProtocol)?,
        guestStopped: @escaping () -> Void
    ) throws(XboxHostFailure) -> XboxSession {
        openSessionLog(sharedMemoryName: request.sharedMemoryName)
        let library = try XemuLibrary(corePath: request.corePath)
        let options = try XboxOptions(request.options)
        let discOffset = try discOffset(atPath: request.contentPath)
        let shm = try mapSharedMemory(named: request.sharedMemoryName)
        // The app unlinks the tap's name as soon as start replies, so it is opened here or never.
        let tap = XboxAudio.openTap(sharedMemoryName: request.sharedMemoryName)
        var started = false
        defer {
            if !started {
                if let tap {
                    cartridge_tap_unmap(tap)
                }
                cartridge_shm_unmap(shm)
            }
        }
        try checkSurfaces(request.frameSurfaces)
        try prepareDrives(library, options: options)
        try createConfigDirectory(options.configDirectory)
        let callbacks = XboxCallbacks(
            frames: XboxFrames(
                shm: shm,
                tap: tap,
                guestFrames: library.guestFrames,
                client: client,
                width: UInt32(baseWidth),
                height: UInt32(baseHeight)
            ),
            pad: XboxPad(shm: shm),
            audio: XboxAudio(shm: shm, tap: tap),
            guestStopped: guestStopped
        )
        var config = CartridgeXemuConfig()
        config.dvd_offset = discOffset
        config.render_scale = renderScale
        config.start_stopped = options.boot == .restore
        config.surfaces = (
            Unmanaged.passUnretained(request.frameSurfaces[0]),
            Unmanaged.passUnretained(request.frameSurfaces[1])
        )
        try launch(library, config: config, options: options, contentPath: request.contentPath, callbacks: callbacks)
        started = true
        return XboxSession(library: library, request: request, options: options, shm: shm, tap: tap)
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if !awaitingRestore {
            setRunning(!paused)
        }
        cartridge_shm_set_paused(shm, paused ? 1 : 0)
    }

    func reset() {
        let status = library.reset()
        if status != CARTRIDGE_XEMU_OK {
            XboxHostLog.session.error("cartridge_xemu_reset returned status \(status.rawValue)")
        }
    }

    func setRunning(_ running: Bool) {
        let status = library.setRunning(running)
        if status != CARTRIDGE_XEMU_OK {
            XboxHostLog.session.error("cartridge_xemu_set_running returned status \(status.rawValue)")
        }
    }

    func stop(collectsGarbage: Bool) {
        guard !stopped else { return }
        stopped = true
        awaitingRestore = false
        setRunning(false)
        if collectsGarbage {
            collectSnapshotGarbage()
        }
        library.stop()
        if let tap {
            cartridge_tap_unmap(tap)
        }
        cartridge_shm_unmap(shm)
    }

    static func nowNs() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    static func milliseconds(since startNs: UInt64) -> UInt64 {
        (nowNs() - startNs) / 1_000_000
    }

    private static func openSessionLog(sharedMemoryName: String) {
        guard let token = CartridgeSharedMemoryLayout.sessionToken(fromName: sharedMemoryName) else {
            XboxHostLog.session.error("session-log-unnamed")
            return
        }
        LogFile.shared.open(LogFile.sessionFile(token: token))
        XboxHostLog.session.notice("helper-start pid=\(getpid()) core=\(XemuLibrary.fileName)")
    }

    private static func discOffset(atPath path: String) throws(XboxHostFailure) -> UInt64 {
        let offset: UInt64?
        do {
            let handle = try FileHandle(forReadingFrom: URL(filePath: path))
            offset = try XboxVolume.partitionOffset(of: handle, fileSize: handle.seekToEnd())
        } catch {
            throw XboxHostFailure(code: .contentLoadFailed, message: "disc: \(error.localizedDescription)")
        }
        guard let offset else {
            throw XboxHostFailure(code: .contentLoadFailed, message: "disc has no Xbox volume")
        }
        return offset
    }

    private static func mapSharedMemory(
        named name: String
    ) throws(XboxHostFailure) -> UnsafeMutablePointer<CartridgeSharedMemory> {
        guard name.hasPrefix(CartridgeSharedMemoryLayout.name(for: "")) else {
            throw XboxHostFailure(code: .sharedMemoryUnavailable, message: "unexpected shared memory name")
        }
        guard let shm = cartridge_shm_open(name) else {
            let failure = errno
            throw XboxHostFailure(
                code: .sharedMemoryUnavailable,
                message: "shm_open: \(String(cString: strerror(failure))) (errno \(failure))"
            )
        }
        return shm
    }

    private static func checkSurfaces(_ surfaces: [IOSurface]) throws(XboxHostFailure) {
        let minimum = FrameSurfaceSize.xbox
        guard surfaces.count == FrameSurfaceFormat.count, surfaces.allSatisfy({
            $0.pixelFormat == FrameSurfaceFormat.pixelFormat && $0.width >= minimum.width && $0.height >= minimum.height
        }) else {
            throw XboxHostFailure(
                code: .surfacesUnavailable,
                message: "expected \(FrameSurfaceFormat.count) BGRA surfaces of at least \(minimum.width)x\(minimum.height)"
            )
        }
    }

    private static func prepareDrives(_ library: XemuLibrary, options: XboxOptions) throws(XboxHostFailure) {
        try checkDrive(options.eepromPath.withCString(library.prepareEEPROM), call: "cartridge_xemu_prepare_eeprom")
        if !FileManager.default.fileExists(atPath: options.baseDrivePath) {
            let began = nowNs()
            try checkDrive(
                options.baseDrivePath.withCString(library.formatBaseDrive),
                call: "cartridge_xemu_format_base_drive"
            )
            XboxHostLog.session.notice("xbox-base-created ms=\(milliseconds(since: began))")
        }
        if !FileManager.default.fileExists(atPath: options.gameDrivePath) {
            let began = nowNs()
            let status = options.gameDrivePath.withCString { drive in
                options.baseDrivePath.withCString { library.createGameDrive(drive, $0) }
            }
            try checkDrive(status, call: "cartridge_xemu_create_game_drive")
            XboxHostLog.session.notice("xbox-drive-created ms=\(milliseconds(since: began))")
        }
    }

    private static func checkDrive(_ status: CartridgeXemuStatus, call: String) throws(XboxHostFailure) {
        guard status != CARTRIDGE_XEMU_OK else { return }
        let code: CoreHostErrorCode = status == CARTRIDGE_XEMU_DISK_FULL ? .diskFull : .coreLoadFailed
        throw XboxHostFailure(code: code, call: call, status: status)
    }

    private static func createConfigDirectory(_ path: String) throws(XboxHostFailure) {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw XboxHostFailure(code: .coreLoadFailed, message: "config directory: \(error.localizedDescription)")
        }
    }

    private static func launch(
        _ library: XemuLibrary,
        config: CartridgeXemuConfig,
        options: XboxOptions,
        contentPath: String,
        callbacks: XboxCallbacks
    ) throws(XboxHostFailure) {
        let strings = [
            options.bootROMPath,
            options.flashPath,
            options.eepromPath,
            options.gameDrivePath,
            contentPath,
            options.configDirectory,
        ]
        let copies = strings.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        let paths = copies.compactMap { $0.map { UnsafePointer($0) } }
        guard paths.count == strings.count else {
            throw XboxHostFailure(code: .coreLoadFailed, message: "strdup failed")
        }
        var config = config
        config.bootrom_path = paths[0]
        config.flash_path = paths[1]
        config.eeprom_path = paths[2]
        config.hdd_path = paths[3]
        config.dvd_path = paths[4]
        config.config_directory = paths[5]
        var host = callbacks.host()
        let status = library.start(&config, &host)
        guard status == CARTRIDGE_XEMU_OK else {
            throw XboxHostFailure(code: startFailureCode(status), call: "cartridge_xemu_start", status: status)
        }
    }

    private static func startFailureCode(_ status: CartridgeXemuStatus) -> CoreHostErrorCode {
        switch status {
        case CARTRIDGE_XEMU_DISC_UNREADABLE: .contentLoadFailed
        case CARTRIDGE_XEMU_DISK_FULL: .diskFull
        case CARTRIDGE_XEMU_AUDIO_FAILED: .audioUnavailable
        case CARTRIDGE_XEMU_ALREADY_STARTED: .alreadyStarted
        default: .coreLoadFailed
        }
    }
}
