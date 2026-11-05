enum Route: Equatable {
    case launch
    case welcome
    case denied
    case scanning
    case library
    case gamePanel(GameID)
    case settings
    case about
    case controller(ControllerGuideTab)
    case play(GameID)

    enum Screen: Hashable {
        case launch
        case welcome
        case denied
        case browse
        case gamePanel
        case settings
        case about
        case controller
        case play
    }

    var screen: Screen {
        switch self {
        case .launch: .launch
        case .welcome: .welcome
        case .denied: .denied
        case .scanning, .library: .browse
        case .gamePanel: .gamePanel
        case .settings: .settings
        case .about: .about
        case .controller: .controller
        case .play: .play
        }
    }

    var keepsBIOSResult: Bool {
        switch self {
        case .gamePanel, .settings: true
        default: false
        }
    }

    var isPlay: Bool {
        if case .play = self {
            return true
        }
        return false
    }
}
