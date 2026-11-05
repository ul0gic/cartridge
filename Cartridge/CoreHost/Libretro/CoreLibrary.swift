import Foundation

struct CoreInfo {
    let needFullpath: Bool
    let validExtensions: String
}

final class CoreLibrary {
    private typealias SetEnvironment = @convention(c) (retro_environment_t?) -> Void
    private typealias SetVideoRefresh = @convention(c) (retro_video_refresh_t?) -> Void
    private typealias SetAudioSample = @convention(c) (retro_audio_sample_t?) -> Void
    private typealias SetAudioSampleBatch = @convention(c) (retro_audio_sample_batch_t?) -> Void
    private typealias SetInputPoll = @convention(c) (retro_input_poll_t?) -> Void
    private typealias SetInputState = @convention(c) (retro_input_state_t?) -> Void
    private typealias NoArguments = @convention(c) () -> Void
    private typealias GetSystemInfo = @convention(c) (UnsafeMutablePointer<retro_system_info>) -> Void
    private typealias GetSystemAVInfo = @convention(c) (UnsafeMutablePointer<retro_system_av_info>) -> Void
    private typealias LoadGame = @convention(c) (UnsafePointer<retro_game_info>) -> Bool
    private typealias SetControllerPortDevice = @convention(c) (UInt32, UInt32) -> Void
    private typealias SerializeSize = @convention(c) () -> Int
    private typealias Serialize = @convention(c) (UnsafeMutableRawPointer, Int) -> Bool
    private typealias Unserialize = @convention(c) (UnsafeRawPointer, Int) -> Bool
    private typealias GetMemoryData = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
    private typealias GetMemorySize = @convention(c) (UInt32) -> Int
    private typealias CheatSet = @convention(c) (UInt32, Bool, UnsafePointer<CChar>) -> Void

    private let setEnvironmentSymbol: SetEnvironment
    private let setVideoRefreshSymbol: SetVideoRefresh
    private let setAudioSampleSymbol: SetAudioSample
    private let setAudioSampleBatchSymbol: SetAudioSampleBatch
    private let setInputPollSymbol: SetInputPoll
    private let setInputStateSymbol: SetInputState
    private let initSymbol: NoArguments
    private let deinitSymbol: NoArguments
    private let runSymbol: NoArguments
    private let resetSymbol: NoArguments
    private let unloadGameSymbol: NoArguments
    private let getSystemInfoSymbol: GetSystemInfo
    private let getSystemAVInfoSymbol: GetSystemAVInfo
    private let loadGameSymbol: LoadGame
    private let setControllerPortDeviceSymbol: SetControllerPortDevice
    private let serializeSizeSymbol: SerializeSize
    private let serializeSymbol: Serialize
    private let unserializeSymbol: Unserialize
    private let getMemoryDataSymbol: GetMemoryData
    private let getMemorySizeSymbol: GetMemorySize
    private let cheatResetSymbol: NoArguments
    private let cheatSetSymbol: CheatSet

    init(path: String) throws(CoreHostFailure) {
        // The handle is never dlclose'd: the helper exits after the session and re-dlopen crashes cores.
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw CoreHostFailure(code: .coreLoadFailed, message: "dlopen: \(String(cString: dlerror()))")
        }
        setEnvironmentSymbol = try Self.symbol(handle, "retro_set_environment")
        setVideoRefreshSymbol = try Self.symbol(handle, "retro_set_video_refresh")
        setAudioSampleSymbol = try Self.symbol(handle, "retro_set_audio_sample")
        setAudioSampleBatchSymbol = try Self.symbol(handle, "retro_set_audio_sample_batch")
        setInputPollSymbol = try Self.symbol(handle, "retro_set_input_poll")
        setInputStateSymbol = try Self.symbol(handle, "retro_set_input_state")
        initSymbol = try Self.symbol(handle, "retro_init")
        deinitSymbol = try Self.symbol(handle, "retro_deinit")
        runSymbol = try Self.symbol(handle, "retro_run")
        resetSymbol = try Self.symbol(handle, "retro_reset")
        unloadGameSymbol = try Self.symbol(handle, "retro_unload_game")
        getSystemInfoSymbol = try Self.symbol(handle, "retro_get_system_info")
        getSystemAVInfoSymbol = try Self.symbol(handle, "retro_get_system_av_info")
        loadGameSymbol = try Self.symbol(handle, "retro_load_game")
        setControllerPortDeviceSymbol = try Self.symbol(handle, "retro_set_controller_port_device")
        serializeSizeSymbol = try Self.symbol(handle, "retro_serialize_size")
        serializeSymbol = try Self.symbol(handle, "retro_serialize")
        unserializeSymbol = try Self.symbol(handle, "retro_unserialize")
        getMemoryDataSymbol = try Self.symbol(handle, "retro_get_memory_data")
        getMemorySizeSymbol = try Self.symbol(handle, "retro_get_memory_size")
        cheatResetSymbol = try Self.symbol(handle, "retro_cheat_reset")
        cheatSetSymbol = try Self.symbol(handle, "retro_cheat_set")
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws(CoreHostFailure) -> T {
        guard let pointer = dlsym(handle, name) else {
            throw CoreHostFailure(code: .symbolMissing, message: "missing symbol \(name)")
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    func setEnvironment(_ callback: retro_environment_t) {
        setEnvironmentSymbol(callback)
    }

    func setCallbacks(
        video: retro_video_refresh_t,
        audioSample: retro_audio_sample_t,
        audioSampleBatch: retro_audio_sample_batch_t,
        inputPoll: retro_input_poll_t,
        inputState: retro_input_state_t
    ) {
        setVideoRefreshSymbol(video)
        setAudioSampleSymbol(audioSample)
        setAudioSampleBatchSymbol(audioSampleBatch)
        setInputPollSymbol(inputPoll)
        setInputStateSymbol(inputState)
    }

    func initialize() {
        cartridge_call_void(initSymbol)
    }

    func deinitialize() {
        cartridge_call_void(deinitSymbol)
    }

    func run() {
        cartridge_call_void(runSymbol)
    }

    func reset() {
        cartridge_call_void(resetSymbol)
    }

    func unloadGame() {
        cartridge_call_void(unloadGameSymbol)
    }

    func systemInfo() -> CoreInfo {
        var info = retro_system_info()
        cartridge_call_get_system_info(getSystemInfoSymbol, &info)
        return CoreInfo(
            needFullpath: info.need_fullpath,
            validExtensions: info.valid_extensions.map { String(cString: $0) } ?? ""
        )
    }

    func systemAVInfo() -> retro_system_av_info {
        var info = retro_system_av_info()
        cartridge_call_get_system_av_info(getSystemAVInfoSymbol, &info)
        return info
    }

    func loadGame(path: String, data: UnsafeRawPointer?, size: Int) -> Bool {
        path.withCString { cPath in
            var game = retro_game_info(path: cPath, data: data, size: size, meta: nil)
            return cartridge_call_load_game(loadGameSymbol, &game)
        }
    }

    func setControllerPortDevice(port: UInt32, device: UInt32) {
        cartridge_call_set_controller_port_device(setControllerPortDeviceSymbol, port, device)
    }

    func serializeSize() -> Int {
        cartridge_call_serialize_size(serializeSizeSymbol)
    }

    func serialize(into buffer: UnsafeMutableRawPointer, size: Int) -> Bool {
        cartridge_call_serialize(serializeSymbol, buffer, size)
    }

    func unserialize(from buffer: UnsafeRawPointer, size: Int) -> Bool {
        cartridge_call_unserialize(unserializeSymbol, buffer, size)
    }

    func cheatReset() {
        cartridge_call_void(cheatResetSymbol)
    }

    func cheatSet(index: UInt32, enabled: Bool, code: String) {
        code.withCString { cartridge_call_cheat_set(cheatSetSymbol, index, enabled, $0) }
    }

    func saveRAM() -> (pointer: UnsafeMutableRawPointer, size: Int)? {
        let id = UInt32(RETRO_MEMORY_SAVE_RAM)
        let size = cartridge_call_get_memory_size(getMemorySizeSymbol, id)
        guard size > 0, let pointer = cartridge_call_get_memory_data(getMemoryDataSymbol, id) else {
            return nil
        }
        return (pointer, size)
    }
}
