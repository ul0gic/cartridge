import Foundation

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private static let peerRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"C7X64A66VW\""

    private var acceptedConnection = false

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard !acceptedConnection else {
            newConnection.resume()
            newConnection.invalidate()
            return true
        }
        acceptedConnection = true
        newConnection.setCodeSigningRequirement(Self.peerRequirement)
        newConnection.exportedInterface = NSXPCInterface.coreHost()
        newConnection.exportedObject = CoreHostService(connection: newConnection)
        newConnection.remoteObjectInterface = NSXPCInterface(with: CoreHostClientProtocol.self)
        newConnection.interruptionHandler = {
            LogFile.shared.flush()
            exit(0)
        }
        newConnection.invalidationHandler = {
            LogFile.shared.flush()
            exit(0)
        }
        newConnection.resume()
        return true
    }
}
