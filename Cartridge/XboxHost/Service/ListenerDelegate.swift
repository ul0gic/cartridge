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
        let service = XboxHostService(connection: newConnection)
        newConnection.exportedObject = service
        newConnection.remoteObjectInterface = NSXPCInterface(with: CoreHostClientProtocol.self)
        newConnection.interruptionHandler = {
            service.connectionLost()
        }
        newConnection.invalidationHandler = {
            service.connectionLost()
        }
        newConnection.resume()
        return true
    }
}
