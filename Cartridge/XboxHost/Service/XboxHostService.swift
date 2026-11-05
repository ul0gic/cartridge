import Foundation
import IOSurface

final class XboxHostService: NSObject, CoreHostProtocol {
    private static let connectionLossTimeout = DispatchTimeInterval.seconds(10)

    private let queue = DispatchQueue(label: "io.corelift.Cartridge.xbox", qos: .userInitiated)
    private let connection: NSXPCConnection
    private var session: XboxSession?
    private var startAttempted = false
    private var stopping = false

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    // swiftlint:disable:next function_parameter_count - XPC signature fixed by contracts.md
    func start(
        corePath: String,
        contentPath: String,
        systemDirectory _: String,
        saveDirectory: String,
        batterySavePath _: String,
        options: [String: String],
        controllerPortDevice _: UInt32,
        sharedMemoryName: String,
        frameSurfaces: [IOSurface],
        reply: @escaping (NSError?, Int32, Int32, Int32, Int32, Double, Double, Double) -> Void
    ) {
        let request = XboxStartRequest(
            corePath: corePath,
            contentPath: contentPath,
            saveDirectory: saveDirectory,
            options: options,
            sharedMemoryName: sharedMemoryName,
            frameSurfaces: frameSurfaces
        )
        let client = connection.remoteObjectProxyWithErrorHandler { error in
            XboxHostLog.session.error("client message failed: \(error.localizedDescription)")
        } as? any CoreHostClientProtocol
        queue.async { [self] in
            do throws(XboxHostFailure) {
                guard !startAttempted else {
                    throw XboxHostFailure(code: .alreadyStarted, message: "start was already called")
                }
                startAttempted = true
                let session = try XboxSession.start(request, client: client) { [weak self] in
                    self?.guestStopped()
                }
                self.session = session
                reply(
                    nil,
                    XboxSession.baseWidth,
                    XboxSession.baseHeight,
                    Int32(FrameSurfaceSize.xbox.width),
                    Int32(FrameSurfaceSize.xbox.height),
                    XboxFrames.aspectRatio,
                    XboxSession.fps,
                    Double(XboxAudio.sampleRate)
                )
                session.scheduleRestoreTimeout(on: queue)
            } catch {
                XboxHostLog.session.error("start failed: \(error.message)")
                reply(error.nsError, 0, 0, 0, 0, 0, 0, 0)
            }
        }
    }

    func setPaused(_ paused: Bool, reply: @escaping () -> Void) {
        queue.async { [self] in
            session?.setPaused(paused)
            reply()
        }
    }

    func reset(reply: @escaping () -> Void) {
        queue.async { [self] in
            session?.reset()
            reply()
        }
    }

    func saveState(toPath path: String, reply: @escaping (NSError?) -> Void) {
        queue.async { [self] in
            reply(failure { () throws(XboxHostFailure) in try requireSession().saveState(toPath: path) })
        }
    }

    func loadState(fromPath path: String, reply: @escaping (NSError?) -> Void) {
        queue.async { [self] in
            reply(failure { () throws(XboxHostFailure) in try requireSession().loadState(fromPath: path) })
        }
    }

    func writeBatterySave(reply: @escaping (NSError?, Bool) -> Void) {
        queue.async {
            reply(nil, false)
        }
    }

    func setDisc(index: Int, reply: @escaping (NSError?) -> Void) {
        queue.async { [self] in
            reply(failure { () throws(XboxHostFailure) in
                throw XboxHostFailure(code: .noDiskControl, message: "Xbox has no disc control (disc \(index))")
            })
        }
    }

    func setCheats(_ codes: [String], reply: @escaping (NSError?) -> Void) {
        queue.async { [self] in
            reply(failure { () throws(XboxHostFailure) in
                guard codes.isEmpty else {
                    throw XboxHostFailure(code: .cheatRejected, message: "Xbox has no cheats (\(codes.count) codes)")
                }
            })
        }
    }

    func batterySaveSize(reply: @escaping (Int) -> Void) {
        queue.async {
            reply(0)
        }
    }

    func stop(reply: @escaping () -> Void) {
        queue.async { [self] in
            stopping = true
            session?.stop(collectsGarbage: true)
            session = nil
            XboxHostLog.session.notice("helper-stop pid=\(getpid())")
            reply()
        }
    }

    func connectionLost() {
        let began = XboxSession.nowNs()
        // An orphan helper would keep the game drive locked against the next session, so a hung stop still exits.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.connectionLossTimeout) {
            XboxHostLog.session.error("xbox-connection-lost-timeout")
            LogFile.shared.flush()
            exit(0)
        }
        queue.async { [self] in
            stopping = true
            let stopped = session != nil
            session?.stop(collectsGarbage: false)
            session = nil
            XboxHostLog.session.notice(
                "xbox-connection-lost stopped=\(stopped ? 1 : 0) ms=\(XboxSession.milliseconds(since: began))"
            )
            LogFile.shared.flush()
            exit(0)
        }
    }

    private func guestStopped() {
        XboxHostLog.session.notice("guest-stopped")
        queue.async { [self] in
            guard !stopping else { return }
            stopping = true
            session?.stop(collectsGarbage: true)
            session = nil
            XboxHostLog.session.notice("helper-exit reason=guest-stopped pid=\(getpid())")
            LogFile.shared.flush()
            exit(0)
        }
    }

    private func requireSession() throws(XboxHostFailure) -> XboxSession {
        guard let session else {
            throw XboxHostFailure(code: .notStarted, message: "no session is running")
        }
        return session
    }

    private func failure(_ operation: () throws(XboxHostFailure) -> Void) -> NSError? {
        do throws(XboxHostFailure) {
            try operation()
            return nil
        } catch {
            XboxHostLog.session.error("\(error.message)")
            return error.nsError
        }
    }
}
