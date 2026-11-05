import Foundation

enum XboxDiscError: Error {
    case noVolume
    case noXBE
    case badXBE

    var logReason: String {
        switch self {
        case .noVolume: "no-volume"
        case .noXBE: "no-xbe"
        case .badXBE: "bad-xbe"
        }
    }
}

struct XboxDiscInfo: Sendable {
    private static let sectorSize: UInt64 = 2048
    private static let maxTableBytes = 64 << 10
    private static let entryHeaderBytes = 14
    private static let directoryAttribute: UInt8 = 0x10
    private static let target = Array("DEFAULT.XBE".utf8)
    private static let xbeMagic = Array("XBEH".utf8)
    private static let xbeHeaderBytes = 0x11C
    private static let certificateBytes = 0xB0
    private static let titleNameUnits = 40

    let titleID: UInt32
    let version: UInt32
    let region: UInt32
    let titleName: String

    var serial: String? {
        Self.serial(titleID: titleID)
    }

    static func serial(titleID: UInt32) -> String? {
        let letters = [UInt8(truncatingIfNeeded: titleID >> 24), UInt8(truncatingIfNeeded: titleID >> 16)]
        guard letters.allSatisfy({ (0x41...0x5A).contains($0) }) else { return nil }
        let prefix = letters.map { String(Character(UnicodeScalar($0))) }.joined()
        return prefix + "-" + String(format: "%03d", Int(titleID & 0x7FFF))
    }

    static func read(from url: URL, fileSize: UInt64) throws -> XboxDiscInfo {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let partition = try XboxVolume.partitionOffset(of: handle, fileSize: fileSize) else {
            throw XboxDiscError.noVolume
        }
        let reader = Reader(handle: handle, fileSize: fileSize)
        let descriptor = try reader.read(8, at: partition + XboxVolume.descriptorOffset + 0x14, failing: .noVolume)
        let tableOffset = partition + UInt64(descriptor.u32(at: 0)) * sectorSize
        let tableLength = min(Int(descriptor.u32(at: 4)), maxTableBytes)
        let table = try reader.read(tableLength, at: tableOffset, failing: .noXBE)

        let entry = try findDefaultXBE(in: table)
        let xbeOffset = partition + UInt64(entry.sector) * sectorSize
        let xbeSize = UInt64(entry.size)
        guard xbeSize >= UInt64(xbeHeaderBytes), xbeOffset <= fileSize, xbeSize <= fileSize - xbeOffset else {
            throw XboxDiscError.badXBE
        }

        let header = try reader.read(xbeHeaderBytes, at: xbeOffset, failing: .badXBE)
        let baseAddress = header.u32(at: 0x104)
        let certificateAddress = header.u32(at: 0x118)
        guard header.starts(with: xbeMagic), certificateAddress >= baseAddress else { throw XboxDiscError.badXBE }
        let certificateOffset = UInt64(certificateAddress - baseAddress)
        guard certificateOffset <= xbeSize, xbeSize - certificateOffset >= UInt64(certificateBytes) else {
            throw XboxDiscError.badXBE
        }

        let certificate = try reader.read(certificateBytes, at: xbeOffset + certificateOffset, failing: .badXBE)
        return XboxDiscInfo(
            titleID: certificate.u32(at: 0x08),
            version: certificate.u32(at: 0xAC),
            region: certificate.u32(at: 0xA0),
            titleName: titleName(in: certificate)
        )
    }

    private static func findDefaultXBE(in table: [UInt8]) throws -> (sector: UInt32, size: UInt32) {
        var offset = 0
        for _ in 0..<(table.count / entryHeaderBytes) {
            let nameStart = offset + entryHeaderBytes
            guard nameStart <= table.count else { break }
            let header = table[offset..<nameStart]
            if header.allSatisfy({ $0 == 0xFF }) || header.allSatisfy({ $0 == 0 }) {
                break
            }
            let nameLength = Int(table[offset + 13])
            guard nameLength > 0, nameStart + nameLength <= table.count else { break }

            let name = table[nameStart..<(nameStart + nameLength)].map(uppercased)
            let next: Int
            if name.elementsEqual(target) {
                guard table[offset + 12] & directoryAttribute == 0 else { break }
                return (table.u32(at: offset + 4), table.u32(at: offset + 8))
            } else if name.lexicographicallyPrecedes(target) {
                next = table.u16(at: offset + 2)
            } else {
                next = table.u16(at: offset)
            }
            guard next != 0, next != 0xFFFF else { break }
            offset = next * 4
        }
        throw XboxDiscError.noXBE
    }

    private static func uppercased(_ byte: UInt8) -> UInt8 {
        (0x61...0x7A).contains(byte) ? byte - 0x20 : byte
    }

    private static func titleName(in certificate: [UInt8]) -> String {
        var units: [UInt16] = []
        for index in 0..<titleNameUnits {
            let unit = UInt16(certificate.u16(at: 0x0C + index * 2))
            if unit == 0 {
                break
            }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Reader {
        let handle: FileHandle
        let fileSize: UInt64

        func read(_ count: Int, at offset: UInt64, failing error: XboxDiscError) throws -> [UInt8] {
            guard offset <= fileSize, UInt64(count) <= fileSize - offset else { throw error }
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else { throw error }
            return [UInt8](data)
        }
    }
}

extension [UInt8] {
    fileprivate func u16(at offset: Int) -> Int {
        Int(self[offset]) | Int(self[offset + 1]) << 8
    }

    fileprivate func u32(at offset: Int) -> UInt32 {
        UInt32(u16(at: offset)) | UInt32(u16(at: offset + 2)) << 16
    }
}
