import Foundation

public enum XboxVolume {
    public static let xisoOffset: UInt64 = 0
    public static let redumpOffset: UInt64 = 0x1830_0000
    public static let descriptorOffset: UInt64 = 0x10000
    public static let magic = "MICROSOFT*XBOX*MEDIA"

    public static func partitionOffset(of handle: FileHandle, fileSize: UInt64) throws -> UInt64? {
        let expected = Data(magic.utf8)
        for offset in [xisoOffset, redumpOffset] {
            let start = offset + descriptorOffset
            guard start + UInt64(expected.count) <= fileSize else { continue }
            try handle.seek(toOffset: start)
            if try handle.read(upToCount: expected.count) == expected {
                return offset
            }
        }
        return nil
    }
}
