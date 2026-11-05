enum CoreHostLog {
    static let session = LogChannel(category: "session")
    static let core = LogChannel(category: "core")

    static func recordCoreLine(level: retro_log_level, message: UnsafePointer<CChar>) {
        let fileLevel: LogLevel
        let name: String
        switch level {
        // Core debug lines stay in the unified log only, so a chatty core cannot fill the 50 MB log folder.
        case RETRO_LOG_DEBUG: return
        case RETRO_LOG_INFO: (fileLevel, name) = (.info, "info")
        case RETRO_LOG_WARN: (fileLevel, name) = (.notice, "warn")
        case RETRO_LOG_ERROR: (fileLevel, name) = (.error, "error")
        default: (fileLevel, name) = (.notice, "unknown")
        }
        LogFile.shared.append(
            category: core.category,
            level: fileLevel,
            message: "[\(name)] \(String(cString: message))"
        )
    }
}

extension LogFile {
    static let shared = LogFile(process: "helper", idleFile: nil, prunes: false)
}
