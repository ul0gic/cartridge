import Foundation

enum GameIdentity: Codable, Hashable, Sendable {
    case crc32(UInt32)
    case serial(String)
    case digest(String)
    case xbe(titleID: UInt32, version: UInt32)

    var string: String {
        switch self {
        case .crc32(let value): String(format: "crc-%08X", value)
        case .serial(let value): "serial-\(value)"
        case .digest(let value): "digest-\(value)"
        // swiftlint:disable:next pattern_matching_keywords - swiftformat patternlet inline conflict
        case .xbe(let titleID, let version): String(format: "xbe-%08X-%08X", titleID, version)
        }
    }
}

struct GameID: Hashable, Codable, Sendable {
    let system: GameSystem
    let identity: GameIdentity

    var rawValue: String {
        "\(system.rawValue)/\(identity.string)"
    }

    var saveFolderName: String {
        rawValue
    }
}
