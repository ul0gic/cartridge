import Foundation

extension LogFile {
    static let shared = LogFile(process: "app", idleFile: launchFile(prefix: "app", at: .now), prunes: true)
}
