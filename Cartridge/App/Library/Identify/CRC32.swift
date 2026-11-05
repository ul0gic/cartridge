import zlib

struct CRC32: Sendable {
    private(set) var value: UInt32 = 0

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard let base = bytes.baseAddress else { return }
        let result = crc32(uLong(value), base.assumingMemoryBound(to: Bytef.self), uInt(bytes.count))
        value = UInt32(truncatingIfNeeded: result)
    }
}
