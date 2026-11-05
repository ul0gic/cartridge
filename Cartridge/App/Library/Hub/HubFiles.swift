import Foundation

enum HubFiles {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func isDiskFull(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) || nsError.code == Int(EDQUOT) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            return isDiskFull(underlying)
        }
        return false
    }

    static func storeWriteError(from error: any Error) -> StoreWriteError {
        isDiskFull(error) ? .diskFull : .writeFailed
    }

    static func saveFileError(from error: any Error) -> SaveFileError {
        isDiskFull(error) ? .diskFull : .writeFailed
    }
}
