enum ControllerTransport: Sendable {
    case bluetooth
    case usb
    case unknown
}

struct MenuTilt: Sendable, Equatable {
    static let zero = MenuTilt(x: 0, y: 0)

    let x: Double
    let y: Double
}

struct ControllerInfo: Sendable, Equatable {
    let name: String
    let transport: ControllerTransport
}

enum Direction: Sendable {
    case up
    case down
    case left
    case right
}

enum NavigationAction: Sendable, Equatable {
    case move(Direction)
    case confirm
    case back
    case options
    case secondary
    case pause
    case section(Direction)
    case text(String)
    case erase
}

enum FeedbackKind: Sendable {
    case tick
    case confirm
}

enum InputSource: Sendable {
    case controller
    case keyboard
}

struct NavigationEvent: Sendable, Equatable {
    let action: NavigationAction
    let source: InputSource
    let isRepeat: Bool
}

enum InputMode: Sendable {
    case navigation
    case play
}

enum AnalogStick: Sendable {
    case left
    case right
}

protocol PlayInputSink: AnyObject, Sendable {
    func setJoypad(_ mask: UInt32)
    func setAnalog(_ stick: AnalogStick, x: Int16, y: Int16)
    func setTriggers(left: UInt8, right: UInt8)
    func setSpeed(_ speed: PlaySpeed)
}
