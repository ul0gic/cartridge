import Foundation
import IOSurface

@objc
public protocol CoreHostProtocol {
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
    )
    func setPaused(_ paused: Bool, reply: @escaping () -> Void)
    func reset(reply: @escaping () -> Void)
    func saveState(toPath path: String, reply: @escaping (NSError?) -> Void)
    func loadState(fromPath path: String, reply: @escaping (NSError?) -> Void)
    func writeBatterySave(reply: @escaping (NSError?, Bool) -> Void)
    func setDisc(index: Int, reply: @escaping (NSError?) -> Void)
    func setCheats(_ codes: [String], reply: @escaping (NSError?) -> Void)
    func batterySaveSize(reply: @escaping (Int) -> Void)
    func stop(reply: @escaping () -> Void)
}

@objc
public protocol CoreHostClientProtocol {
    func geometryDidChange(baseWidth: Int32, baseHeight: Int32, aspectRatio: Double)
    func avInfoDidChange(maxWidth: Int32, maxHeight: Int32, fps: Double, sampleRate: Double)
}

extension NSXPCInterface {
    public static func coreHost() -> NSXPCInterface {
        let interface = NSXPCInterface(with: CoreHostProtocol.self)
        let surfaceClasses = Set(NSSet(array: [NSArray.self, IOSurface.self]).compactMap { $0 as? AnyHashable })
        let start = #selector(
            CoreHostProtocol.start(
                corePath:contentPath:systemDirectory:saveDirectory:batterySavePath:
                options:controllerPortDevice:sharedMemoryName:frameSurfaces:reply:
            )
        )
        interface.setClasses(surfaceClasses, for: start, argumentIndex: 8, ofReply: false)
        return interface
    }
}
