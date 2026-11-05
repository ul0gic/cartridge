public enum PlaySpeed: UInt32, Sendable {
    case normal = 0
    case rewind = 1
    case fastForward = 2
}

public enum ActiveSpeed: UInt32, Sendable {
    case normal = 0
    case rewinding = 1
    case rewindHolding = 2
    case fastForward = 3

    public var logName: String {
        switch self {
        case .normal: "normal"
        case .rewinding: "rewind"
        case .rewindHolding: "rewind-holding"
        case .fastForward: "fast-forward"
        }
    }
}
