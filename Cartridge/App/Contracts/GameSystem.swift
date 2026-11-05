import CoreGraphics
import Foundation

enum GameSystem: String, Codable, CaseIterable, Sendable {
    case nes
    case snes
    case genesis
    case n64
    case ps1
    case xbox

    var displayName: String {
        switch self {
        case .nes: "NES"
        case .snes: "SNES"
        case .genesis: "Genesis"
        case .n64: "N64"
        case .ps1: "PS1"
        case .xbox: "Xbox"
        }
    }

    var fileExtensions: [String] {
        switch self {
        case .nes: ["nes"]
        case .snes: ["sfc", "smc"]
        case .genesis: ["md", "gen", "smd", "bin"]
        case .n64: ["z64", "v64", "n64"]
        case .ps1: ["cue", "chd", "pbp", "m3u"]
        case .xbox: ["iso", "xiso"]
        }
    }

    var databaseFolder: String {
        switch self {
        case .nes: "Nintendo - Nintendo Entertainment System"
        case .snes: "Nintendo - Super Nintendo Entertainment System"
        case .genesis: "Sega - Mega Drive - Genesis"
        case .n64: "Nintendo - Nintendo 64"
        case .ps1: "Sony - PlayStation"
        case .xbox: "Microsoft - Xbox"
        }
    }

    var tileAspect: CGFloat {
        switch self {
        case .nes, .genesis: 0.7
        case .snes, .n64: 1.43
        case .ps1: 1.0
        case .xbox: 0.71
        }
    }

    var coreFileName: String {
        switch self {
        case .nes: "mesen_libretro.dylib"
        case .snes: "snes9x_libretro.dylib"
        case .genesis: "genesis_plus_gx_libretro.dylib"
        case .n64: "mupen64plus_next_libretro.dylib"
        case .ps1: "mednafen_psx_libretro.dylib"
        case .xbox: "libxemu.dylib"
        }
    }

    var libraryOrder: Int {
        switch self {
        case .nes: 0
        case .snes: 1
        case .genesis: 2
        case .n64: 3
        case .ps1: 4
        case .xbox: 5
        }
    }

    var helperServiceName: String {
        self == .xbox ? "io.corelift.Cartridge.XboxHost" : "io.corelift.Cartridge.CoreHost"
    }

    var coreLibraryURL: URL? {
        guard self == .xbox else {
            return Bundle.main.privateFrameworksURL?
                .appending(path: "Cores", directoryHint: .isDirectory)
                .appending(path: coreFileName, directoryHint: .notDirectory)
        }
        return Bundle.main.bundleURL
            .appending(path: "Contents/XPCServices/XboxHost.xpc/Contents/Frameworks", directoryHint: .isDirectory)
            .appending(path: coreFileName, directoryHint: .notDirectory)
    }

    var frameSurfaceSize: FrameSurfaceSize {
        self == .xbox ? .xbox : .libretro
    }

    var startBudget: Duration {
        self == .xbox ? .seconds(40) : .seconds(10)
    }
}
