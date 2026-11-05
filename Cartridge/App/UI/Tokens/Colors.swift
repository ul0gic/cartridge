import SwiftUI

enum Palette {
    static let background = Color("background")
    static let surface = Color("surface")
    static let material = Color("material")
    static let glassTint = Color("material").opacity(0.3)
    static let materialStroke = Color("material-stroke")
    static let textPrimary = Color("text-primary")
    static let textSecondary = Color("text-secondary")
    static let textTertiary = Color("text-tertiary")
    static let focusRing = Color("focus-ring")
    static let focusGap = Color("focus-gap")
    static let actionFill = Color("action-fill")
    static let actionText = Color("action-text")
    static let controlFill = Color("control-fill")
    static let controlStroke = Color("control-stroke")
    static let keycapStroke = Color("keycap-stroke")
    static let tileLoading = Color("tile-loading")
    static let tileLoadingSheen = Color("tile-loading-sheen")
    static let scrimGame = Color("scrim-game")
    static let shadowLift = Color("shadow-lift")
    static let shadowArt = Color("shadow-art")
    static let success = Color("success")
    static let warning = Color("warning")
    static let danger = Color("danger")
    static let bandDangerFill = Color("band-danger-fill")
    static let bandWarningFill = Color("band-warning-fill")
    static let resumeMark = Color("resume-mark")

    static let playBackground = Color("play-background")
    static let textOnArt = Color("text-on-art")
    static let artScrim = Color("art-scrim")
    static let placeholderSheen = Color("ph-sheen")
    static let placeholderTextShadow = Color("ph-text-shadow")
    static let brand1 = Color("brand-1")
    static let brand2 = Color("brand-2")
    static let brand3 = Color("brand-3")

    static let placeholderCount = 12

    static func console(_ system: GameSystem) -> Color {
        let rgb = consoleRGB(system)
        return Color(red: Double(rgb.red), green: Double(rgb.green), blue: Double(rgb.blue))
    }

    static func consoleRGB(_ system: GameSystem) -> LightColor {
        switch system {
        case .nes: LightColor(red: 0.78, green: 0.13, blue: 0.23)
        case .snes: LightColor(red: 0.36, green: 0.29, blue: 0.72)
        case .genesis: LightColor(red: 0.12, green: 0.37, blue: 0.84)
        case .n64: LightColor(red: 0.12, green: 0.56, blue: 0.31)
        case .ps1: LightColor(red: 0.43, green: 0.48, blue: 0.56)
        case .xbox: LightColor(red: 0.353, green: 0.706, blue: 0.235)
        }
    }

    static let brandRGB = LightColor(red: 0.42, green: 0.33, blue: 0.95)

    static func placeholder(_ index: Int) -> PlaceholderStops {
        PlaceholderStops(
            top: Color("ph-\(index)-a"),
            middle: Color("ph-\(index)-b"),
            bottom: Color("ph-\(index)-c")
        )
    }
}

struct PlaceholderStops {
    let top: Color
    let middle: Color
    let bottom: Color
}

struct LightColor: Equatable {
    let red: Float
    let green: Float
    let blue: Float
}
