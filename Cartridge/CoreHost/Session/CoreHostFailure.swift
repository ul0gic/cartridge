import Foundation

struct CoreHostFailure: Error {
    let code: CoreHostErrorCode
    let message: String

    init(code: CoreHostErrorCode, message: String) {
        self.code = code
        self.message = message.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    var nsError: NSError {
        NSError(domain: coreHostErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func posix(_ code: CoreHostErrorCode, _ operation: String, errno failure: Int32) -> CoreHostFailure {
        CoreHostFailure(code: code, message: "\(operation): \(String(cString: strerror(failure))) (errno \(failure))")
    }
}
