public let coreHostErrorDomain = "io.corelift.Cartridge.CoreHost"

public enum CoreHostErrorCode: Int {
    case coreLoadFailed = 1
    case symbolMissing = 2
    case contentLoadFailed = 3
    case serializeFailed = 4
    case unserializeFailed = 5
    case writeFailed = 6
    case diskFull = 7
    case noDiskControl = 8
    case invalidDiscIndex = 9
    case alreadyStarted = 10
    case notStarted = 11
    case sharedMemoryUnavailable = 12
    case surfacesUnavailable = 13
    case audioUnavailable = 14
    case cheatRejected = 15
}
