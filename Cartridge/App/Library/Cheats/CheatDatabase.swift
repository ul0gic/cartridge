import Foundation

final class CheatDatabase: Sendable {
    private static let empty = CheatLookup(files: [], entries: [])

    private let roots: [URL]

    init(bundle: Bundle = .main) {
        roots = [bundle.resourceURL?.appending(path: "Cheats", directoryHint: .isDirectory), StoragePaths.cheats]
            .compactMap(\.self)
    }

    @concurrent
    func cheats(for game: GameRecord) async -> CheatLookup {
        guard let databaseName = game.databaseName else { return Self.empty }
        let listed = roots.flatMap { root in
            Self.files(in: root.appending(path: game.system.databaseFolder), system: game.system)
        }

        let wanted = CheatFileName(databaseName)
        let titleMatches = listed
            .filter { $0.pathExtension.lowercased() == "cht" }
            .map { (url: $0, name: CheatFileName($0.deletingPathExtension().lastPathComponent)) }
            .filter { $0.name.baseTitle == wanted.baseTitle }
        let qualified = titleMatches.filter { $0.name.isCandidate(for: wanted) }

        let chosen = (qualified.isEmpty ? titleMatches : qualified)
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        var files: [String] = []
        var entries: [CheatEntry] = []
        for match in chosen {
            let fileEntries = Self.entries(in: match.url, named: match.name, system: game.system)
            if !fileEntries.isEmpty {
                files.append(match.url.lastPathComponent)
                entries += fileEntries
            }
        }
        return CheatLookup(files: files, entries: entries)
    }

    private static func files(in folder: URL, system: GameSystem) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            LibraryLog.logger.error("cheat-folder-unreadable system=\(system.rawValue)")
            return []
        }
    }

    private static func entries(in url: URL, named name: CheatFileName, system: GameSystem) -> [CheatEntry] {
        let fileName = url.lastPathComponent
        let raw: [CheatFile.Entry]
        do {
            raw = try CheatFile.entries(at: url)
        } catch {
            LibraryLog.logger.error("cheat-file-unreadable system=\(system.rawValue) reason=\(error)")
            return []
        }
        return raw.compactMap { entry in
            guard case .success(let code) = CheatCodeFormat.normalize(entry.code, for: system) else { return nil }
            return CheatEntry(
                key: CheatKey(file: fileName, index: entry.index),
                description: entry.description,
                code: code,
                device: name.device ?? "Codes"
            )
        }
    }
}
