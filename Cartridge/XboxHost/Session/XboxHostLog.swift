import os

enum XboxHostLog {
    static let session = LogChannel(category: "session")
    static let core = LogChannel(category: "core")
    private static let coreUnifiedOnly = Logger(subsystem: LogFile.subsystem, category: "core")

    static func recordCoreLine(level: CartridgeXemuLogLevel, message: UnsafePointer<CChar>) {
        let text = String(cString: message)
        switch level {
        // xemu's debug lines stay in the unified log only, so a chatty library cannot fill the 50 MB log folder.
        case CARTRIDGE_XEMU_LOG_DEBUG: coreUnifiedOnly.debug("[debug] \(text, privacy: .public)")
        case CARTRIDGE_XEMU_LOG_INFO: core.info("[info] \(text)")
        case CARTRIDGE_XEMU_LOG_WARN: core.notice("[warn] \(text)")
        case CARTRIDGE_XEMU_LOG_ERROR: core.error("[error] \(text)")
        default: core.notice("[level-\(level.rawValue)] \(text)")
        }
    }
}

extension LogFile {
    static let shared = LogFile(process: "xbox-helper", idleFile: nil, prunes: false)
}
