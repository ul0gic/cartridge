import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class XboxFirmwareStore: XboxFirmwareStoring {
    private(set) var installed: Set<XboxFirmwareFile> = []

    var isReady: Bool {
        installed.count == XboxFirmwareFile.allCases.count
    }

    init() {
        installed = Self.installedFiles()
    }

    func importFirmware(from folder: URL) async -> XboxFirmwareImport {
        let result = await Task.detached { Self.copyMatches(from: folder) }.value
        installed = Self.installedFiles()
        return result
    }

    nonisolated private static func installedFiles() -> Set<XboxFirmwareFile> {
        Set(XboxFirmwareFile.allCases.filter { file in
            let url = StoragePaths.xboxFirmware(file)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  let data = try? read(url, size: size),
                  case .accepted(file) = XboxFirmwareCatalog.classify(data)
            else { return false }
            return true
        })
    }

    nonisolated private static func copyMatches(from folder: URL) -> XboxFirmwareImport {
        let folderName = folder.lastPathComponent
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
        } catch {
            LibraryLog.logger.error("xbox firmware folder unreadable: \(error.localizedDescription)")
            return logged(XboxFirmwareImport(folderName: folderName, filesChecked: 0, imported: [], refused: []))
        }

        var filesChecked = 0
        var imported = Set<XboxFirmwareFile>()
        var refused: [XboxFirmwareRefusal] = []
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            filesChecked += 1
            guard let size = values?.fileSize else { continue }
            let data: Data
            do {
                guard let candidate = try read(url, size: size) else { continue }
                data = candidate
            } catch {
                LibraryLog.logger.error("xbox firmware candidate unreadable: \(error.localizedDescription)")
                continue
            }
            switch XboxFirmwareCatalog.classify(data) {
            case .accepted(let file):
                if store(data, as: file) {
                    imported.insert(file)
                }
            case .refused(let reason):
                refused.append(XboxFirmwareRefusal(fileName: url.lastPathComponent, reason: reason))
            case nil:
                continue
            }
        }
        return logged(XboxFirmwareImport(
            folderName: folderName,
            filesChecked: filesChecked,
            imported: XboxFirmwareFile.allCases.filter(imported.contains),
            refused: refused
        ))
    }

    nonisolated private static func read(_ url: URL, size: Int) throws -> Data? {
        guard XboxFirmwareCatalog.candidateSizes.contains(size) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: size + 1), data.count == size else { return nil }
        return data
    }

    nonisolated private static func store(_ data: Data, as file: XboxFirmwareFile) -> Bool {
        do {
            try FileManager.default.createDirectory(at: StoragePaths.system, withIntermediateDirectories: true)
            try data.write(to: StoragePaths.xboxFirmware(file), options: .atomic)
            return true
        } catch {
            LibraryLog.logger.error("xbox firmware copy failed: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated private static func logged(_ result: XboxFirmwareImport) -> XboxFirmwareImport {
        let files = result.imported.isEmpty ? "none" : result.imported.map(\.rawValue).joined(separator: ",")
        LibraryLog.logger.info(
            "xbox-firmware-import folder=\(result.folderName) checked=\(result.filesChecked) imported=\(files) refused=\(result.refused.count)"
        )
        return result
    }
}

private enum XboxFirmwareCandidate: Equatable {
    case accepted(XboxFirmwareFile)
    case refused(XboxFirmwareRefusalReason)
}

private struct FlashImage: Hashable {
    let bytes: Int
    let md5: String
}

private enum XboxFirmwareCatalog {
    static let bootROMSize = 512
    static let flashSizes: Set = [262_144, 524_288, 1_048_576]
    static let candidateSizes = flashSizes.union([bootROMSize])
    static let bootHeaderOffset = 8
    static let bootHeader: [UInt8] = [0x65, 0xD0, 0x16, 0x2B]

    static let bootROM = "D49C52A4102F6DF7BCF8D0617AC475ED"
    static let refusedBootROMs: [String: XboxFirmwareRefusalReason] = [
        "196A5F59A13382C185636E691D6C323D": .damagedBootROM,
        "2870D58A459C745D7CC4C6122CEB3DCB": .bootROM11,
    ]

    static let complex4627: Set = [
        FlashImage(bytes: 1_048_576, md5: "EC00E31E746DE2473ACFE7903C5A4CB7"),
        FlashImage(bytes: 524_288, md5: "325B6FD3BF5018663535247A9B791F72"),
        FlashImage(bytes: 262_144, md5: "4132E24C64B7A8D4EA34FF448051E923"),
        FlashImage(bytes: 1_048_576, md5: "39CEE882148A87F93CB440B99DDE3CEB"),
        FlashImage(bytes: 524_288, md5: "96A8366AF7633654BF7A0A59696B0786"),
        FlashImage(bytes: 262_144, md5: "70B54E6CD91F59D4932E7ED776F9267E"),
        FlashImage(bytes: 262_144, md5: "3D2C1A663C523F08389180A868B3D335"),
        FlashImage(bytes: 1_048_576, md5: "21445C6F28FCA7285B0F167EA770D1E5"),
    ]

    static let retail: Set = [
        FlashImage(bytes: 262_144, md5: "542C62CB976A4993C8C5027DFF9638CE"),
        FlashImage(bytes: 1_048_576, md5: "E8B39B98CF775496C1C76E4F7756E6ED"),
        FlashImage(bytes: 262_144, md5: "F20CD7574BB4B2A69810B2E9F766A90D"),
        FlashImage(bytes: 1_048_576, md5: "B49A417511B2DBB485AA255A32A319D1"),
        FlashImage(bytes: 262_144, md5: "CF36AD116E2404AFF022533B07B11004"),
        FlashImage(bytes: 1_048_576, md5: "C0A543CE695201ACA87C51B3A5CDF8C8"),
        FlashImage(bytes: 262_144, md5: "C3DB66C8E212974AFEC6D6087DDBB8EF"),
        FlashImage(bytes: 1_048_576, md5: "430B3EDF0F1EA5C77F47845ED3CBD22B"),
        FlashImage(bytes: 262_144, md5: "769898E9682E1F5D065B5961460D03E6"),
        FlashImage(bytes: 262_144, md5: "E455FEB286DFC16272AD94D773C24460"),
        FlashImage(bytes: 262_144, md5: "E27BBF815C67BCBF359907A68EA46978"),
        FlashImage(bytes: 262_144, md5: "C5907D241DE37C22B083B6E30FA934B0"),
    ]

    static func classify(_ data: Data) -> XboxFirmwareCandidate? {
        if data.count == bootROMSize {
            let digest = md5(of: data)
            if digest == bootROM {
                return .accepted(.bootROM)
            }
            return refusedBootROMs[digest].map(XboxFirmwareCandidate.refused)
        }
        guard flashSizes.contains(data.count),
              data.dropFirst(bootHeaderOffset).prefix(bootHeader.count).elementsEqual(bootHeader)
        else { return nil }
        let image = FlashImage(bytes: data.count, md5: md5(of: data))
        if complex4627.contains(image) {
            return .accepted(.flash)
        }
        return .refused(retail.contains(image) ? .retailBIOS : .unknownBIOS)
    }

    private static func md5(of data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }
}
