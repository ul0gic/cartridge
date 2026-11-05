enum LibraryError: Error, Sendable, Equatable {
    case folderMissing(path: String)
    case accessDenied(path: String, location: ProtectedLocation?)
    case notAFolder(path: String)
    case indexUnreadable
}

enum SaveFailure: Sendable, Equatable {
    case diskFull
    case writeFailed
    case coreRefused
}

enum PlayError: Error, Sendable, Equatable {
    case coreMissing(GameSystem)
    case contentUnreadable
    case helperUnavailable
    case startTimeout
    case crashed
    case saveFailed(SaveFailure)
    case loadFailed
    case quitSaveFailed(SaveFailure)
    case discChangeFailed
    case cheatsRejected
}
