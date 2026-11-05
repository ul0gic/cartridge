import Foundation
import Metal

enum SessionStart: Sendable, Equatable {
    case resume
    case fresh
    case slot(SlotNumber)
}

enum DisplayLook: String, CaseIterable, Codable, Sendable {
    case original
    case sharp
    case crt

    var displayName: String {
        switch self {
        case .original: "Original"
        case .sharp: "Sharp"
        case .crt: "CRT"
        }
    }
}

enum TriggerRole: Sendable {
    case speedControls
    case gameButtons
}

enum FaceLayout: Sendable {
    case positional
    case jumpOnCross
}

struct PlayFeatures: OptionSet, Sendable {
    let rawValue: UInt8

    static let rewind = PlayFeatures(rawValue: 1)
    static let fastForward = PlayFeatures(rawValue: 2)
    static let cheats = PlayFeatures(rawValue: 4)
    static let saveFile = PlayFeatures(rawValue: 8)
}

extension GameSystem {
    var triggerRole: TriggerRole {
        switch self {
        case .nes, .snes, .genesis: .speedControls
        case .n64, .ps1, .xbox: .gameButtons
        }
    }

    var playFeatures: PlayFeatures {
        switch self {
        case .nes, .snes, .genesis, .ps1: [.rewind, .fastForward, .cheats, .saveFile]
        case .n64: [.fastForward, .cheats, .saveFile]
        case .xbox: []
        }
    }

    var faceLayout: FaceLayout {
        self == .nes ? .jumpOnCross : .positional
    }
}

enum PlayControlEvent: Sendable, Equatable {
    case rewindHeld(Bool)
    case captureRequested
}

struct SlotNumber: Hashable, Comparable, Sendable {
    private static let range = 1...10

    static let all = range.compactMap(SlotNumber.init)

    let value: Int

    init?(_ value: Int) {
        guard Self.range.contains(value) else { return nil }
        self.value = value
    }

    var fileStem: String {
        String(format: "slot-%02d", value)
    }

    static func < (lhs: SlotNumber, rhs: SlotNumber) -> Bool {
        lhs.value < rhs.value
    }
}

extension SlotNumber: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard let slot = SlotNumber(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "slot \(value) is outside 1...10")
        }
        self = slot
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct SlotRecord: Codable, Sendable, Equatable {
    let number: SlotNumber
    let savedAt: Date
    let core: String
    let hasThumbnail: Bool
}

struct SlotIndexFile: Codable {
    let version: Int
    let slots: [SlotRecord]
}

enum StoreWriteError: Error, Sendable, Equatable {
    case writeFailed
    case diskFull
}

struct CheatKey: Hashable, Codable, Sendable {
    let file: String
    let index: Int

    var rawValue: String {
        "\(file)#\(index)"
    }
}

extension CheatKey {
    init?(rawValue: String) {
        guard let separator = rawValue.lastIndex(of: "#"),
              let index = Int(rawValue[rawValue.index(after: separator)...]), index >= 0
        else { return nil }
        let file = String(rawValue[..<separator])
        guard !file.isEmpty else { return nil }
        self.init(file: file, index: index)
    }
}

struct CheatEntry: Identifiable, Sendable, Equatable {
    let key: CheatKey
    let description: String
    let code: String
    let device: String

    var id: CheatKey {
        key
    }
}

struct CheatLookup: Sendable, Equatable {
    let files: [String]
    let entries: [CheatEntry]
}

struct MyCode: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let code: String
    let addedAt: Date
    var isEnabled: Bool
}

struct CheatSettings: Codable, Sendable, Equatable {
    static let empty = CheatSettings(version: 1, enabled: [], myCodes: [])

    let version: Int
    var enabled: [String]
    var myCodes: [MyCode]
}

struct CheatFormat: Sendable, Equatable {
    let name: String
    let pattern: String
}

enum CheatCodeError: Error, Sendable, Equatable {
    case empty
    case tooLong
    case noFormat
}

struct SaveBackup: Identifiable, Sendable, Equatable {
    let url: URL
    let createdAt: Date
    let bytes: Int

    var id: URL {
        url
    }
}

enum SaveFileError: Error, Sendable, Equatable {
    case noBatterySave
    case notARegularFile
    case wrongSize(expected: Int, actual: Int)
    case unreadable
    case writeFailed
    case diskFull
}

enum CaptureKind: String, Codable, Sendable {
    case screenshot
    case clip
    case gif

    var fileExtension: String {
        switch self {
        case .screenshot: "png"
        case .clip: "mp4"
        case .gif: "gif"
        }
    }
}

struct CaptureItem: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let kind: CaptureKind
    let fileName: String
    let gameID: GameID
    let gameTitle: String
    let capturedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let durationSeconds: Double?
}

struct GalleryIndexFile: Codable {
    let version: Int
    let items: [CaptureItem]
}

enum GalleryError: Error, Sendable, Equatable {
    case writeFailed
    case unsupportedIndexVersion
    case diskFull
    case missingFile
    case notAClip
    case gifFailed
}

enum CaptureError: Error, Sendable, Equatable {
    case encoderFailed
    case nothingCaptured
    case writeFailed
    case diskFull
}

struct PresentedFrame: Sendable, Equatable {
    let sequence: UInt64
    let displayNs: UInt64
    let aspectRatio: Double
}

struct CaptureTarget {
    let texture: any MTLTexture
    let complete: @Sendable (Bool) -> Void
}

@MainActor
protocol CaptureFrameSink: AnyObject {
    func videoTarget(for frame: PresentedFrame, device: any MTLDevice) -> CaptureTarget?
    func stillTarget(device: any MTLDevice, aspectRatio: Double) -> CaptureTarget?
}

@MainActor
protocol GalleryStoring: AnyObject {
    func newFileURL(kind: CaptureKind, gameTitle: String, capturedAt: Date) -> URL
    func add(_ item: CaptureItem) throws(GalleryError)
}
