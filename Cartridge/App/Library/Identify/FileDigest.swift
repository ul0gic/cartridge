import CryptoKit
import Foundation

enum FileDigest {
    private static let chunkSize = 1 << 20
    private static let identityPrefixBytes = 16 << 20
    private static let identityHexLength = 16

    static func cartridgeCRCs(of url: URL, system: GameSystem) throws -> [UInt32] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var stored = CRC32()
        var normalised = CRC32()
        var isNormalisable = false
        var byteOrder: N64ByteOrder?
        var isFirstChunk = true

        while var chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            chunk.withUnsafeBytes { stored.update($0) }

            if isFirstChunk {
                isFirstChunk = false
                switch system {
                case .nes:
                    isNormalisable = NESHeader.isPresent(in: chunk)
                case .n64:
                    byteOrder = N64ByteOrder(leadingBytes: chunk)
                    isNormalisable = byteOrder != nil && byteOrder != .z64
                case .snes, .genesis, .ps1, .xbox:
                    break
                }
                if system == .nes, isNormalisable {
                    chunk.removeFirst(NESHeader.length)
                }
            }

            if isNormalisable {
                if system == .n64, let byteOrder {
                    byteOrder.convertToZ64(&chunk)
                }
                chunk.withUnsafeBytes { normalised.update($0) }
            }
        }

        return isNormalisable ? [normalised.value, stored.value] : [stored.value]
    }

    static func identityDigest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)

        var hasher = SHA256()
        var remaining = identityPrefixBytes
        while remaining > 0, let chunk = try handle.read(upToCount: min(chunkSize, remaining)), !chunk.isEmpty {
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        withUnsafeBytes(of: fileSize.littleEndian) { hasher.update(bufferPointer: $0) }

        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(identityHexLength))
    }
}
