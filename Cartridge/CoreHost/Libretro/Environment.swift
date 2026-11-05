import Foundation

struct DiskControlCallbacks {
    var setEjectState: retro_set_eject_state_t?
    var setImageIndex: retro_set_image_index_t?
    var getNumImages: retro_get_num_images_t?
    var isExtended = false
}

final class Environment {
    private enum Command {
        static let mask: UInt32 = 0xFFFF

        static func base(_ id: Int32) -> UInt32 {
            UInt32(id) & mask
        }

        static let systemDirectory = base(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY)
        static let saveDirectory = base(RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY)
        static let setPixelFormat = base(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT)
        static let getVariable = base(RETRO_ENVIRONMENT_GET_VARIABLE)
        static let setVariables = base(RETRO_ENVIRONMENT_SET_VARIABLES)
        static let logInterface = base(RETRO_ENVIRONMENT_GET_LOG_INTERFACE)
        static let setGeometry = base(RETRO_ENVIRONMENT_SET_GEOMETRY)
        static let setSystemAVInfo = base(RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO)
        static let canDupe = base(RETRO_ENVIRONMENT_GET_CAN_DUPE)
        static let diskControlVersion = base(RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION)
        static let setDiskControl = base(RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE)
        static let setDiskControlExt = base(RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE)
        static let audioVideoEnable = base(RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE)

        static let accepted: Set<UInt32> = [
            base(RETRO_ENVIRONMENT_SET_CORE_OPTIONS),
            base(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL),
            base(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2),
            base(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL),
            base(RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS),
            base(RETRO_ENVIRONMENT_SET_CONTROLLER_INFO),
            base(RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL),
            base(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME),
            base(RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS),
            base(RETRO_ENVIRONMENT_SET_MEMORY_MAPS),
            base(RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS),
            base(RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE),
            base(RETRO_ENVIRONMENT_SET_MESSAGE),
            base(RETRO_ENVIRONMENT_SET_MESSAGE_EXT),
            base(RETRO_ENVIRONMENT_GET_INPUT_BITMASKS),
        ]

        static let declined: Set<UInt32> = [
            base(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE),
            base(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION),
            base(RETRO_ENVIRONMENT_SET_HW_RENDER),
            base(RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER),
            base(RETRO_ENVIRONMENT_SET_AUDIO_BUFFER_STATUS_CALLBACK),
        ]
    }

    private let systemDirectory: UnsafeMutablePointer<CChar>
    private let saveDirectory: UnsafeMutablePointer<CChar>
    private var options: [String: String]
    private let client: (any CoreHostClientProtocol)?
    private var valuePointers: [String: UnsafeMutablePointer<CChar>] = [:]
    private var reportedUnknown = Set<UInt32>()
    private var pendingFramePeriod: UInt64?

    private(set) var pixelFormat = PixelFormat.zeroRGB1555
    private(set) var rejectedPixelFormat: UInt32?
    private(set) var diskControl = DiskControlCallbacks()
    var requestsFastSavestates = false

    init?(
        systemDirectory: String,
        saveDirectory: String,
        options: [String: String],
        client: (any CoreHostClientProtocol)?
    ) {
        guard let system = strdup(systemDirectory), let save = strdup(saveDirectory) else {
            return nil
        }
        self.systemDirectory = system
        self.saveDirectory = save
        self.options = options
        self.client = client
    }

    deinit {
        free(systemDirectory)
        free(saveDirectory)
        valuePointers.values.forEach { free($0) }
    }

    func takePendingFramePeriod() -> UInt64? {
        defer { pendingFramePeriod = nil }
        return pendingFramePeriod
    }

    func handle(_ command: UInt32, _ data: UnsafeMutableRawPointer?) -> Bool {
        let base = command & Command.mask
        if Command.accepted.contains(base) {
            return true
        }
        if Command.declined.contains(base) {
            return false
        }
        switch base {
        case Command.setPixelFormat:
            return setPixelFormat(data)
        case Command.setVariables:
            registerVariables(data)
            return true
        case Command.setGeometry:
            return setGeometry(data)
        case Command.setSystemAVInfo:
            return setSystemAVInfo(data)
        case Command.setDiskControl:
            return registerDiskControl(data, extended: false)
        case Command.setDiskControlExt:
            return registerDiskControl(data, extended: true)
        default:
            return answerQuery(base, data)
        }
    }

    private func answerQuery(_ base: UInt32, _ data: UnsafeMutableRawPointer?) -> Bool {
        guard let data else {
            return reject(base)
        }
        switch base {
        case Command.systemDirectory:
            data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = UnsafePointer(systemDirectory)
        case Command.saveDirectory:
            data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = UnsafePointer(saveDirectory)
        case Command.getVariable:
            return answerVariable(data.assumingMemoryBound(to: retro_variable.self))
        case Command.logInterface:
            cartridge_fill_log_callback(data.assumingMemoryBound(to: retro_log_callback.self))
        case Command.canDupe:
            data.assumingMemoryBound(to: Bool.self).pointee = true
        case Command.diskControlVersion:
            data.assumingMemoryBound(to: UInt32.self).pointee = 1
        case Command.audioVideoEnable:
            var flags = RETRO_AV_ENABLE_VIDEO.rawValue | RETRO_AV_ENABLE_AUDIO.rawValue
            if requestsFastSavestates {
                flags |= RETRO_AV_ENABLE_FAST_SAVESTATES.rawValue
            }
            data.assumingMemoryBound(to: Int32.self).pointee = Int32(flags)
        default:
            return reject(base)
        }
        return true
    }

    private func reject(_ base: UInt32) -> Bool {
        if reportedUnknown.insert(base).inserted {
            CoreHostLog.core.debug("unhandled environment command \(base)")
        }
        return false
    }

    private func setPixelFormat(_ data: UnsafeMutableRawPointer?) -> Bool {
        guard let data else {
            return false
        }
        let requested = data.assumingMemoryBound(to: retro_pixel_format.self).pointee
        guard let format = PixelFormat(requested) else {
            rejectedPixelFormat = requested.rawValue
            return false
        }
        pixelFormat = format
        return true
    }

    private func answerVariable(_ variable: UnsafeMutablePointer<retro_variable>) -> Bool {
        guard let key = variable.pointee.key.map({ String(cString: $0) }), let value = options[key] else {
            return false
        }
        if valuePointers[key] == nil {
            guard let copy = strdup(value) else {
                return false
            }
            valuePointers[key] = copy
        }
        variable.pointee.value = valuePointers[key].map { UnsafePointer($0) }
        return true
    }

    /// Unpinned keys take the first listed value, as RetroArch does (core_option_manager.c, default_index = 0).
    private func registerVariables(_ data: UnsafeMutableRawPointer?) {
        guard var entry = data?.assumingMemoryBound(to: retro_variable.self) else {
            return
        }
        while let key = entry.pointee.key {
            let name = String(cString: key)
            let value = entry.pointee.value.map { String(cString: $0) } ?? ""
            if options[name] == nil, let first = Self.defaultValue(of: value) {
                options[name] = first
            }
            let resolved = options[name] ?? ""
            CoreHostLog.core.notice("variable \(name)=\(resolved)")
            entry += 1
        }
    }

    private static func defaultValue(of declaration: String) -> String? {
        guard let separator = declaration.range(of: "; ") else { return nil }
        let values = declaration[separator.upperBound...]
        return values.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    private func setGeometry(_ data: UnsafeMutableRawPointer?) -> Bool {
        guard let data else {
            return false
        }
        notify(geometry: data.assumingMemoryBound(to: retro_game_geometry.self).pointee)
        return true
    }

    private func setSystemAVInfo(_ data: UnsafeMutableRawPointer?) -> Bool {
        guard let data else {
            return false
        }
        let info = data.assumingMemoryBound(to: retro_system_av_info.self).pointee
        guard let period = FramePacing.periodNs(fps: info.timing.fps) else {
            return false
        }
        pendingFramePeriod = period
        notify(geometry: info.geometry)
        client?.avInfoDidChange(
            maxWidth: Int32(clamping: info.geometry.max_width),
            maxHeight: Int32(clamping: info.geometry.max_height),
            fps: info.timing.fps,
            sampleRate: info.timing.sample_rate
        )
        return true
    }

    private func notify(geometry: retro_game_geometry) {
        client?.geometryDidChange(
            baseWidth: Int32(clamping: geometry.base_width),
            baseHeight: Int32(clamping: geometry.base_height),
            aspectRatio: Double(geometry.aspect_ratio)
        )
    }

    private func registerDiskControl(_ data: UnsafeMutableRawPointer?, extended: Bool) -> Bool {
        if diskControl.isExtended && !extended {
            return true
        }
        guard let data else {
            diskControl = DiskControlCallbacks()
            return true
        }
        if extended {
            let callbacks = data.assumingMemoryBound(to: retro_disk_control_ext_callback.self).pointee
            diskControl = DiskControlCallbacks(
                setEjectState: callbacks.set_eject_state,
                setImageIndex: callbacks.set_image_index,
                getNumImages: callbacks.get_num_images,
                isExtended: true
            )
        } else {
            let callbacks = data.assumingMemoryBound(to: retro_disk_control_callback.self).pointee
            diskControl = DiskControlCallbacks(
                setEjectState: callbacks.set_eject_state,
                setImageIndex: callbacks.set_image_index,
                getNumImages: callbacks.get_num_images
            )
        }
        return true
    }
}
