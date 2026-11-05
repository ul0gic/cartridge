import SwiftUI

struct ConsolePalette {
    let lead: Color
    let card: Color
    let cardText: Color
    let stripe: [Color]

    var shadow: Color {
        lead.mix(with: .black, by: 0.72)
    }

    var light: Color {
        lead.mix(with: .white, by: 0.46)
    }

    static func of(_ system: GameSystem) -> ConsolePalette {
        switch system {
        case .nes:
            ConsolePalette(lead: rgb(0xB3221C), card: rgb(0xD12B23), cardText: .white, stripe: [
                rgb(0xD21F2D), rgb(0xC8C8C4), rgb(0x6A6B70),
            ])
        case .snes:
            ConsolePalette(lead: rgb(0x5B40B3), card: rgb(0xDCD7CC), cardText: rgb(0x221C38), stripe: [
                rgb(0x7552CF), rgb(0xA99BE6), rgb(0xD8D3C8),
            ])
        case .genesis:
            ConsolePalette(lead: rgb(0x1435B8), card: rgb(0x1D3FE0), cardText: .white, stripe: [
                rgb(0x1D5AD8), rgb(0x6FA4FF), rgb(0xB9BDC7),
            ])
        case .n64:
            ConsolePalette(lead: rgb(0x0E6E3A), card: rgb(0x13834A), cardText: .white, stripe: [
                rgb(0xE1262F), rgb(0xF5B800), rgb(0x12A150),
            ])
        case .ps1:
            ConsolePalette(lead: rgb(0x4E5868), card: rgb(0x6F747C), cardText: .white, stripe: [
                rgb(0xE2231A), rgb(0xF2B705), rgb(0x2E62C9),
            ])
        case .xbox:
            ConsolePalette(lead: rgb(0x357A1F), card: rgb(0x5AB43C), cardText: rgb(0x0B1A07), stripe: [
                rgb(0x5AB43C), rgb(0xC9CCC8), rgb(0x1B1D1B),
            ])
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension EnvironmentValues {
    @Entry var consoleSystem: GameSystem?
}
