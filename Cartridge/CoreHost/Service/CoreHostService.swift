import Foundation
import IOSurface

final class CoreHostService: NSObject, CoreHostProtocol {
    private let runner = CoreRunner()
    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    // swiftlint:disable:next function_parameter_count - XPC signature fixed by contracts.md
    func start(
        corePath: String,
        contentPath: String,
        systemDirectory: String,
        saveDirectory: String,
        batterySavePath: String,
        options: [String: String],
        controllerPortDevice: UInt32,
        sharedMemoryName: String,
        frameSurfaces: [IOSurface],
        reply: @escaping (NSError?, Int32, Int32, Int32, Int32, Double, Double, Double) -> Void
    ) {
        let request = StartRequest(
            corePath: corePath,
            contentPath: contentPath,
            systemDirectory: systemDirectory,
            saveDirectory: saveDirectory,
            batterySavePath: batterySavePath,
            options: options,
            controllerPortDevice: controllerPortDevice,
            sharedMemoryName: sharedMemoryName,
            frameSurfaces: frameSurfaces
        )
        let client = connection.remoteObjectProxyWithErrorHandler { error in
            CoreHostLog.session.error("client message failed: \(error.localizedDescription)")
        } as? any CoreHostClientProtocol
        runner.submit { [runner] in
            do throws(CoreHostFailure) {
                let info = try runner.begin(request, client: client)
                runner.session?.historyDidJump()
                reply(
                    nil,
                    info.baseWidth,
                    info.baseHeight,
                    info.maxWidth,
                    info.maxHeight,
                    info.aspectRatio,
                    info.fps,
                    info.sampleRate
                )
            } catch {
                CoreHostLog.session.error("start failed: \(error.message)")
                reply(error.nsError, 0, 0, 0, 0, 0, 0, 0)
            }
        }
    }

    func setPaused(_ paused: Bool, reply: @escaping () -> Void) {
        runner.submit { [runner] in
            runner.setPaused(paused)
            reply()
        }
    }

    func reset(reply: @escaping () -> Void) {
        runner.submit { [runner] in
            runner.session?.reset()
            runner.session?.historyDidJump()
            reply()
        }
    }

    func saveState(toPath path: String, reply: @escaping (NSError?) -> Void) {
        runner.submit { [runner] in
            reply(Self.failure { () throws(CoreHostFailure) in
                try runner.requireSession().stateStore.save(toPath: path)
            })
        }
    }

    func loadState(fromPath path: String, reply: @escaping (NSError?) -> Void) {
        runner.submit { [runner] in
            reply(Self.failure { () throws(CoreHostFailure) in
                let session = try runner.requireSession()
                try session.loadState(fromPath: path)
                session.historyDidJump()
                runner.showFrameIfPaused()
            })
        }
    }

    func writeBatterySave(reply: @escaping (NSError?, Bool) -> Void) {
        runner.submit { [runner] in
            do throws(CoreHostFailure) {
                try reply(nil, runner.requireSession().battery.write())
            } catch {
                reply(error.nsError, false)
            }
        }
    }

    func setDisc(index: Int, reply: @escaping (NSError?) -> Void) {
        runner.submit { [runner] in
            reply(Self.failure { () throws(CoreHostFailure) in
                let session = try runner.requireSession()
                try session.setDisc(index: index)
                session.historyDidJump()
            })
        }
    }

    func setCheats(_ codes: [String], reply: @escaping (NSError?) -> Void) {
        runner.submit { [runner] in
            reply(Self.failure { () throws(CoreHostFailure) in try runner.requireSession().cheats.set(codes) })
        }
    }

    func batterySaveSize(reply: @escaping (Int) -> Void) {
        runner.submit { [runner] in
            reply(runner.session?.battery.size ?? 0)
        }
    }

    func stop(reply: @escaping () -> Void) {
        runner.submit { [runner, connection] in
            runner.shutdown()
            reply()
            connection.scheduleSendBarrierBlock {
                LogFile.shared.flush()
                exit(0)
            }
        }
    }

    private static func failure(_ operation: () throws(CoreHostFailure) -> Void) -> NSError? {
        do throws(CoreHostFailure) {
            try operation()
            return nil
        } catch {
            CoreHostLog.session.error("\(error.message)")
            return error.nsError
        }
    }
}
