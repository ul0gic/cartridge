import Foundation

struct PlayRecord: Codable, Sendable {
    var lastPlayedAt: Date?
    var resumeStateAt: Date?
    var manualStateAt: Date?
    var batterySaveAt: Date?
    var discIndex: Int
    var playSeconds: TimeInterval?
    var continueHiddenAt: Date?
}

struct LibrarySelection: Codable, Sendable {
    let rowKey: String
    let gameID: GameID
}

struct LibraryIndex: Codable, Sendable {
    let version: Int
    var romFolderPath: String
    var scannedAt: Date
    var fileCount: Int
    var games: [GameRecord]
    var lastSelection: LibrarySelection?
}

struct ScanProgress: Sendable, Equatable {
    var folderName: String
    var folderPath: String
    var filesFound: Int
    var filesChecked: Int
    var gamesFound: Int
    var perSystem: [GameSystem: Int]
    var isFinished: Bool
}

enum ProtectedLocation: Codable, Hashable, Sendable {
    case desktop
    case documents
    case downloads
    case iCloudDrive
    case removableVolume(name: String)
    case networkVolume(name: String)

    var displayName: String {
        switch self {
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .iCloudDrive: "iCloud Drive"
        case .removableVolume(let name), .networkVolume(let name): "files on \(name)"
        }
    }
}
