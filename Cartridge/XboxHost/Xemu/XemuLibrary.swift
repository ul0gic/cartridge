import Foundation

struct XemuLibrary {
    typealias AbiVersion = @convention(c) () -> UInt32
    typealias PathCall = @convention(c) (UnsafePointer<CChar>) -> CartridgeXemuStatus
    typealias CreateGameDrive = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> CartridgeXemuStatus
    typealias Start = @convention(c) (
        UnsafePointer<CartridgeXemuConfig>,
        UnsafePointer<CartridgeXemuHost>
    ) -> CartridgeXemuStatus
    typealias SetRunning = @convention(c) (Bool) -> CartridgeXemuStatus
    typealias Reset = @convention(c) () -> CartridgeXemuStatus
    typealias SnapshotVisitor = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
    typealias ListSnapshots = @convention(c) (SnapshotVisitor?, UnsafeMutableRawPointer?) -> CartridgeXemuStatus
    typealias GuestFrames = @convention(c) () -> UInt64
    typealias Stop = @convention(c) () -> Void

    static let fileName = "libxemu.dylib"

    let prepareEEPROM: PathCall
    let formatBaseDrive: PathCall
    let createGameDrive: CreateGameDrive
    let start: Start
    let setRunning: SetRunning
    let reset: Reset
    let saveSnapshot: PathCall
    let loadSnapshot: PathCall
    let deleteSnapshot: PathCall
    let listSnapshots: ListSnapshots
    let guestFrames: GuestFrames
    let stop: Stop

    init(corePath: String) throws(XboxHostFailure) {
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/Frameworks/\(Self.fileName)")
        guard URL(filePath: corePath).standardizedFileURL.path == bundled.standardizedFileURL.path else {
            throw XboxHostFailure(code: .coreLoadFailed, message: "core path is not the bundled \(Self.fileName)")
        }
        // The handle is never dlclose'd: xemu starts once per process and the helper exits after the session.
        guard let handle = dlopen(bundled.path, RTLD_NOW | RTLD_LOCAL) else {
            throw XboxHostFailure(code: .coreLoadFailed, message: "dlopen: \(String(cString: dlerror()))")
        }
        let abiVersion: AbiVersion = try Self.symbol(handle, "cartridge_xemu_abi_version")
        let version = abiVersion()
        guard version == CARTRIDGE_XEMU_ABI_VERSION else {
            throw XboxHostFailure(
                code: .coreLoadFailed,
                message: "ABI version \(version), expected \(CARTRIDGE_XEMU_ABI_VERSION)"
            )
        }
        prepareEEPROM = try Self.symbol(handle, "cartridge_xemu_prepare_eeprom")
        formatBaseDrive = try Self.symbol(handle, "cartridge_xemu_format_base_drive")
        createGameDrive = try Self.symbol(handle, "cartridge_xemu_create_game_drive")
        start = try Self.symbol(handle, "cartridge_xemu_start")
        setRunning = try Self.symbol(handle, "cartridge_xemu_set_running")
        reset = try Self.symbol(handle, "cartridge_xemu_reset")
        saveSnapshot = try Self.symbol(handle, "cartridge_xemu_save_snapshot")
        loadSnapshot = try Self.symbol(handle, "cartridge_xemu_load_snapshot")
        deleteSnapshot = try Self.symbol(handle, "cartridge_xemu_delete_snapshot")
        listSnapshots = try Self.symbol(handle, "cartridge_xemu_list_snapshots")
        guestFrames = try Self.symbol(handle, "cartridge_xemu_guest_frames")
        stop = try Self.symbol(handle, "cartridge_xemu_stop")
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws(XboxHostFailure) -> T {
        guard let pointer = dlsym(handle, name) else {
            throw XboxHostFailure(code: .coreLoadFailed, message: "missing symbol \(name)")
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}
