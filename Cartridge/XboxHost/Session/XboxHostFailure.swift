import Foundation

struct XboxHostFailure: Error {
    let code: CoreHostErrorCode
    let message: String

    init(code: CoreHostErrorCode, message: String) {
        self.code = code
        self.message = message.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    init(code: CoreHostErrorCode, call: String, status: CartridgeXemuStatus) {
        self.init(code: code, message: "\(call) returned status \(status.rawValue)")
    }

    var nsError: NSError {
        NSError(domain: coreHostErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
