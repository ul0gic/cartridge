import IOSurface

public struct FrameSurfaceSize: Sendable {
    public static let libretro = FrameSurfaceSize(width: 1024, height: 576)
    public static let xbox = FrameSurfaceSize(width: 1440, height: 960)

    public let width: Int
    public let height: Int
}

public enum FrameSurfaceFormat {
    public static let pixelFormat: UInt32 = 0x4247_5241
    public static let bytesPerElement = 4
    public static let count = 2

    public static func properties(for size: FrameSurfaceSize) -> [IOSurfacePropertyKey: any Sendable] {
        [
            .width: size.width,
            .height: size.height,
            .pixelFormat: pixelFormat,
            .bytesPerElement: bytesPerElement,
        ]
    }
}
