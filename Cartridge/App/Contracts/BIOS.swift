enum BIOSRegion: String, CaseIterable, Codable, Sendable {
    case northAmerica = "scph5501.bin"
    case japan = "scph5500.bin"
    case europe = "scph5502.bin"

    static let expectedSize = 524_288

    var displayName: String {
        switch self {
        case .northAmerica: "North America"
        case .japan: "Japan"
        case .europe: "Europe"
        }
    }

    var sha1Hex: String {
        switch self {
        case .northAmerica: "0555c6fae8906f3f09baf5988f00e55f88e9f30b"
        case .japan: "b05def971d8ec59f346f2d9ac21fb742e3eb6917"
        case .europe: "f6bc2d1f5eb6593de7d089c425ac681d6fffd3f0"
        }
    }
}

enum BIOSImportResult: Sendable, Equatable {
    case imported([BIOSRegion], folderName: String)
    case noneFound(fileCount: Int, folderName: String)
    case badChecksum(fileName: String, folderName: String)
}

enum XboxFirmwareFile: String, CaseIterable, Codable, Sendable {
    case bootROM = "xbox-mcpx-1.0.bin"
    case flash = "xbox-flash.bin"
}

enum XboxFirmwareRefusalReason: Sendable, Equatable {
    case damagedBootROM
    case bootROM11
    case retailBIOS
    case unknownBIOS
}

struct XboxFirmwareRefusal: Sendable, Equatable {
    let fileName: String
    let reason: XboxFirmwareRefusalReason
}

struct XboxFirmwareImport: Sendable, Equatable {
    let folderName: String
    let filesChecked: Int
    let imported: [XboxFirmwareFile]
    let refused: [XboxFirmwareRefusal]
}
