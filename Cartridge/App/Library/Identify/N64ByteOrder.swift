import Foundation

enum N64ByteOrder {
    case z64
    case v64
    case n64

    private static let wordLength = 4

    init?(leadingBytes: Data) {
        switch Array(leadingBytes.prefix(Self.wordLength)) {
        case [0x80, 0x37, 0x12, 0x40]: self = .z64
        case [0x37, 0x80, 0x40, 0x12]: self = .v64
        case [0x40, 0x12, 0x37, 0x80]: self = .n64
        default: return nil
        }
    }

    func convertToZ64(_ chunk: inout Data) {
        guard self != .z64 else { return }
        chunk.withUnsafeMutableBytes { bytes in
            for start in stride(from: 0, through: bytes.count - Self.wordLength, by: Self.wordLength) {
                switch self {
                case .v64:
                    bytes.swapAt(start, start + 1)
                    bytes.swapAt(start + 2, start + 3)
                case .n64:
                    bytes.swapAt(start, start + 3)
                    bytes.swapAt(start + 1, start + 2)
                case .z64:
                    break
                }
            }
        }
    }
}
