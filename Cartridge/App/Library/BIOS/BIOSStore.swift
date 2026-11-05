import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class BIOSStore: BIOSStoring {
    private(set) var installedRegions: [BIOSRegion] = []

    var isReady: Bool {
        !installedRegions.isEmpty
    }

    init() {
        installedRegions = Self.installed()
    }

    func importBIOS(from folder: URL) async -> BIOSImportResult {
        let result = await Task.detached { Self.copyMatches(from: folder) }.value
        installedRegions = Self.installed()
        return result
    }

    nonisolated private static func installed() -> [BIOSRegion] {
        BIOSRegion.allCases.filter { region in
            let url = StoragePaths.system.appending(path: region.rawValue, directoryHint: .notDirectory)
            return (try? sha1(ofBIOSAt: url)) == region.sha1Hex
        }
    }

    nonisolated private static func sha1(ofBIOSAt url: URL) throws -> String? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: BIOSRegion.expectedSize + 1),
              data.count == BIOSRegion.expectedSize
        else { return nil }
        return hex(of: data)
    }

    nonisolated private static func hex(of data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func copyMatches(from folder: URL) -> BIOSImportResult {
        let folderName = folder.lastPathComponent
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
        } catch {
            LibraryLog.logger.error("bios folder unreadable: \(error.localizedDescription)")
            return .noneFound(fileCount: 0, folderName: folderName)
        }

        var fileCount = 0
        var imported = Set<BIOSRegion>()
        var misnamed: String?
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            fileCount += 1

            if let match = matchingRegion(at: url, size: values?.fileSize) {
                if store(match.data, as: match.region) {
                    imported.insert(match.region)
                }
            } else if isNamedLikeBIOS(url.lastPathComponent) {
                misnamed = misnamed ?? url.lastPathComponent
            }
        }

        if !imported.isEmpty {
            return .imported(BIOSRegion.allCases.filter(imported.contains), folderName: folderName)
        }
        if let misnamed {
            return .badChecksum(fileName: misnamed, folderName: folderName)
        }
        return .noneFound(fileCount: fileCount, folderName: folderName)
    }

    nonisolated private static func matchingRegion(at url: URL, size: Int?) -> (region: BIOSRegion, data: Data)? {
        guard size == BIOSRegion.expectedSize,
              let data = try? Data(contentsOf: url),
              data.count == BIOSRegion.expectedSize
        else { return nil }
        let digest = hex(of: data)
        guard let region = BIOSRegion.allCases.first(where: { $0.sha1Hex == digest }) else { return nil }
        return (region, data)
    }

    nonisolated private static func isNamedLikeBIOS(_ fileName: String) -> Bool {
        let lowered = fileName.lowercased()
        return lowered.hasPrefix("scph") && lowered.hasSuffix(".bin")
    }

    nonisolated private static func store(_ data: Data, as region: BIOSRegion) -> Bool {
        do {
            try FileManager.default.createDirectory(at: StoragePaths.system, withIntermediateDirectories: true)
            try data.write(
                to: StoragePaths.system.appending(path: region.rawValue, directoryHint: .notDirectory),
                options: .atomic
            )
            return true
        } catch {
            LibraryLog.logger.error("bios copy failed: \(error.localizedDescription)")
            return false
        }
    }
}
