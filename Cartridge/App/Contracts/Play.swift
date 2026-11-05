enum QuitOutcome: Sendable, Equatable {
    case saved
    case withoutSaving
}

enum PlaySessionState: Sendable, Equatable {
    case starting
    case running
    case paused
    case quitting
    case ended(QuitOutcome)
    case failed(PlayError)
    case crashed
}

struct FrameGeometry: Sendable, Equatable {
    let width: Int
    let height: Int
    let aspectRatio: Double
}

struct PlayStats: Sendable, Equatable {
    let targetFPS: Double
    let producedLastSecond: Int
    let presentedLastSecond: Int
    let droppedLastSecond: Int
    let underrunsLastSecond: Int
    let longHoldsLastSecond: Int
    let intervalSeconds: Double
}
