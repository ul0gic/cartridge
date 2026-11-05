import Foundation

enum PS1Serial {
    private static let scanLength = 60000
    private static let digitCount = 5
    private static let prefixes = [
        "SCUS_", "SLUS_", "SLES_", "SCED_", "SLPS_", "SLPM_", "SCPS_",
        "SLED_", "SIPS_", "ESPM_", "SCES_", "SLKA_", "SCAJ_",
    ]

    static func read(from url: URL) throws -> String? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let head = try handle.read(upToCount: scanLength) else { return nil }
        return find(in: head)
    }

    private static func find(in data: Data) -> String? {
        var earliest: (offset: Int, serial: String)?
        for prefix in prefixes {
            let needle = Data(prefix.utf8)
            var searchStart = data.startIndex
            while let range = data.range(of: needle, in: searchStart..<data.endIndex) {
                if let serial = serial(prefix: prefix, digitsFrom: range.upperBound, in: data) {
                    if earliest.map({ range.lowerBound < $0.offset }) ?? true {
                        earliest = (range.lowerBound, serial)
                    }
                    break
                }
                searchStart = range.upperBound
            }
        }
        return earliest?.serial
    }

    private static func serial(prefix: String, digitsFrom start: Int, in data: Data) -> String? {
        var digits = ""
        var cursor = start
        while cursor < data.endIndex, digits.count < digitCount {
            let byte = data[cursor]
            if (0x30...0x39).contains(byte) {
                digits.append(Character(UnicodeScalar(byte)))
            } else if byte != 0x2E {
                return nil
            }
            cursor += 1
        }
        guard digits.count == digitCount else { return nil }
        return "\(prefix.dropLast())-\(digits)"
    }
}
