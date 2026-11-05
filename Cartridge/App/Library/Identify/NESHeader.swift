import Foundation

enum NESHeader {
    static let length = 16
    private static let magic: [UInt8] = [0x4E, 0x45, 0x53, 0x1A]

    static func isPresent(in leadingBytes: Data) -> Bool {
        leadingBytes.count >= length && leadingBytes.prefix(magic.count).elementsEqual(magic)
    }
}
