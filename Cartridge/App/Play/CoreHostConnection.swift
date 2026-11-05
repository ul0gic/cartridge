import Foundation
import IOSurface

enum ConnectionEvent: Sendable {
    case interrupted
    case invalidated
}

enum CoreHostCallError: Error {
    case host(code: Int, message: String)
    case transport(String)

    var hostCode: CoreHostErrorCode? {
        guard case .host(let code, _) = self else { return nil }
        return CoreHostErrorCode(rawValue: code)
    }

    var message: String {
        switch self {
        case .host(_, let message), .transport(let message): message
        }
    }

    init(_ error: NSError) {
        if error.domain == coreHostErrorDomain {
            self = .host(code: error.code, message: error.localizedDescription)
        } else {
            self = .transport(error.localizedDescription)
        }
    }
}

extension CoreHostCallError {
    func startFailure(for system: GameSystem) -> PlayError {
        guard let code = hostCode else { return .helperUnavailable }
        switch code {
        case .coreLoadFailed, .symbolMissing:
            return .coreMissing(system)
        case .contentLoadFailed:
            return .contentUnreadable
        case .serializeFailed, .unserializeFailed, .writeFailed, .diskFull, .noDiskControl, .invalidDiscIndex,
             .alreadyStarted, .notStarted, .sharedMemoryUnavailable, .surfacesUnavailable, .audioUnavailable,
             .cheatRejected:
            return .helperUnavailable
        }
    }
}

struct StartReply: Sendable {
    let baseWidth: Int
    let baseHeight: Int
    let maxWidth: Int
    let maxHeight: Int
    let aspectRatio: Double
    let fps: Double
    let sampleRate: Double
}

struct StartRequest {
    let corePath: String
    let contentPath: String
    let systemDirectory: String
    let saveDirectory: String
    let batterySavePath: String
    let controllerPortDevice: LibretroControllerDevice
    let options: [String: String]
    let sharedMemoryName: String
    let frameSurfaces: [IOSurface]
}

// @unchecked: only immutable Sendable closures are stored; the NSObject base is not Sendable.
private final class HostClient: NSObject, CoreHostClientProtocol, @unchecked Sendable {
    private let onGeometry: @Sendable (Int32, Int32, Double) -> Void
    private let onAVInfo: @Sendable (Int32, Int32, Double, Double) -> Void

    init(
        onGeometry: @escaping @Sendable (Int32, Int32, Double) -> Void,
        onAVInfo: @escaping @Sendable (Int32, Int32, Double, Double) -> Void
    ) {
        self.onGeometry = onGeometry
        self.onAVInfo = onAVInfo
    }

    func geometryDidChange(baseWidth: Int32, baseHeight: Int32, aspectRatio: Double) {
        onGeometry(baseWidth, baseHeight, aspectRatio)
    }

    func avInfoDidChange(maxWidth: Int32, maxHeight: Int32, fps: Double, sampleRate: Double) {
        onAVInfo(maxWidth, maxHeight, fps, sampleRate)
    }
}

/// Built outside the @MainActor class: a closure literal made inside it inherits MainActor and traps on the XPC queue.
private enum XPCCompletion {
    typealias Resume<Value: Sendable> = @Sendable (Result<Value, CoreHostCallError>) -> Void

    typealias Fail = @Sendable (CoreHostCallError) -> Void

    static func transportFailure(_ fail: @escaping Fail) -> @Sendable (any Error) -> Void {
        { fail(CoreHostCallError($0 as NSError)) }
    }

    static func empty(_ resume: @escaping Resume<Void>) -> @Sendable () -> Void {
        { resume(.success(())) }
    }

    static func error(_ resume: @escaping Resume<Void>) -> @Sendable (NSError?) -> Void {
        { error in
            if let error {
                resume(.failure(CoreHostCallError(error)))
            } else {
                resume(.success(()))
            }
        }
    }

    static func battery(_ resume: @escaping Resume<Bool>) -> @Sendable (NSError?, Bool) -> Void {
        { error, written in
            if let error {
                resume(.failure(CoreHostCallError(error)))
            } else {
                resume(.success(written))
            }
        }
    }

    static func size(_ resume: @escaping Resume<Int>) -> @Sendable (Int) -> Void {
        { resume(.success($0)) }
    }

    static func start(
        _ resume: @escaping Resume<StartReply>
    ) -> @Sendable (NSError?, Int32, Int32, Int32, Int32, Double, Double, Double) -> Void {
        { error, baseWidth, baseHeight, maxWidth, maxHeight, aspectRatio, fps, sampleRate in
            if let error {
                resume(.failure(CoreHostCallError(error)))
                return
            }
            resume(.success(StartReply(
                baseWidth: Int(baseWidth),
                baseHeight: Int(baseHeight),
                maxWidth: Int(maxWidth),
                maxHeight: Int(maxHeight),
                aspectRatio: aspectRatio,
                fps: fps,
                sampleRate: sampleRate
            )))
        }
    }

    static func interrupted(_ events: AsyncStream<ConnectionEvent>.Continuation) -> @Sendable () -> Void {
        { events.yield(.interrupted) }
    }

    static func invalidated(_ events: AsyncStream<ConnectionEvent>.Continuation) -> @Sendable () -> Void {
        {
            events.yield(.invalidated)
            events.finish()
        }
    }
}

@MainActor
final class CoreHostConnection {
    let events: AsyncStream<ConnectionEvent>
    private let connection: NSXPCConnection
    private let client: HostClient

    init(
        serviceName: String,
        onGeometry: @escaping @Sendable (Int32, Int32, Double) -> Void,
        onAVInfo: @escaping @Sendable (Int32, Int32, Double, Double) -> Void
    ) {
        let (events, continuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        self.events = events
        client = HostClient(onGeometry: onGeometry, onAVInfo: onAVInfo)
        connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = .coreHost()
        connection.exportedInterface = NSXPCInterface(with: CoreHostClientProtocol.self)
        connection.exportedObject = client
        connection.interruptionHandler = XPCCompletion.interrupted(continuation)
        connection.invalidationHandler = XPCCompletion.invalidated(continuation)
        connection.resume()
    }

    func invalidate() {
        connection.invalidate()
    }

    func start(_ request: StartRequest) async throws -> StartReply {
        try await call { host, resume in
            host.start(
                corePath: request.corePath,
                contentPath: request.contentPath,
                systemDirectory: request.systemDirectory,
                saveDirectory: request.saveDirectory,
                batterySavePath: request.batterySavePath,
                options: request.options,
                controllerPortDevice: request.controllerPortDevice.rawValue,
                sharedMemoryName: request.sharedMemoryName,
                frameSurfaces: request.frameSurfaces,
                reply: XPCCompletion.start(resume)
            )
        }
    }

    func setPaused(_ paused: Bool) async throws {
        try await call { host, resume in
            host.setPaused(paused, reply: XPCCompletion.empty(resume))
        }
    }

    func reset() async throws {
        try await call { host, resume in
            host.reset(reply: XPCCompletion.empty(resume))
        }
    }

    func saveState(toPath path: String) async throws {
        try await call { host, resume in
            host.saveState(toPath: path, reply: XPCCompletion.error(resume))
        }
    }

    func loadState(fromPath path: String) async throws {
        try await call { host, resume in
            host.loadState(fromPath: path, reply: XPCCompletion.error(resume))
        }
    }

    func writeBatterySave() async throws -> Bool {
        try await call { host, resume in
            host.writeBatterySave(reply: XPCCompletion.battery(resume))
        }
    }

    func setDisc(index: Int) async throws {
        try await call { host, resume in
            host.setDisc(index: index, reply: XPCCompletion.error(resume))
        }
    }

    func setCheats(_ codes: [String]) async throws {
        try await call { host, resume in
            host.setCheats(codes, reply: XPCCompletion.error(resume))
        }
    }

    func batterySaveSize() async throws -> Int {
        try await call { host, resume in
            host.batterySaveSize(reply: XPCCompletion.size(resume))
        }
    }

    func stop() async throws {
        try await call { host, resume in
            host.stop(reply: XPCCompletion.empty(resume))
        }
    }

    private func call<Value: Sendable>(
        _ send: (any CoreHostProtocol, @escaping XPCCompletion.Resume<Value>) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let resume: XPCCompletion.Resume<Value> = { continuation.resume(with: $0) }
            let proxy = connection.remoteObjectProxyWithErrorHandler(
                XPCCompletion.transportFailure { resume(.failure($0)) }
            )
            guard let host = proxy as? any CoreHostProtocol else {
                resume(.failure(.transport("proxy does not conform to CoreHostProtocol")))
                return
            }
            send(host, resume)
        }
    }
}
