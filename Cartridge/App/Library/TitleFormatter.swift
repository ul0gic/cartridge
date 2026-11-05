import Foundation

enum TitleFormatter {
    struct Parts {
        let title: String
        let tags: [String]
    }

    private struct TitleKey: Hashable {
        let system: GameSystem
        let title: String
    }

    static func parts(ofFileName fileName: String) -> Parts {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return parts(ofDatabaseName: stem.replacingOccurrences(of: "_", with: " "))
    }

    static func sortKey(_ title: String) -> String {
        let lowered = title.lowercased()
        return lowered.hasPrefix("the ") ? String(lowered.dropFirst(4)) : lowered
    }

    static func listing(_ games: [GameRecord]) -> [GameRecord] {
        disambiguate(collapseRevisions(games))
    }

    static func collapseRevisions(_ games: [GameRecord]) -> [GameRecord] {
        var kept: [TitleKey: (offset: Int, revision: String?)] = [:]
        for (offset, game) in games.enumerated() {
            guard let databaseName = game.databaseName else { continue }
            let part = parts(ofDatabaseName: databaseName)
            let revision = part.tags.first(where: isRevision)
            let others = part.tags.filter { !isRevision($0) }
            let key = TitleKey(system: game.system, title: ([part.title] + others).joined(separator: "|"))
            if kept[key].map({ outranks(revision, $0.revision) }) ?? true {
                kept[key] = (offset, revision)
            }
        }
        let keptOffsets = Set(kept.values.map(\.offset))
        return games.enumerated().compactMap { offset, game in
            game.databaseName == nil || keptOffsets.contains(offset) ? game : nil
        }
    }

    static func disambiguate(_ games: [GameRecord]) -> [GameRecord] {
        let parts = games.map(parts(of:))
        var groups: [TitleKey: (count: Int, common: Set<String>)] = [:]
        for (game, part) in zip(games, parts) {
            let key = TitleKey(system: game.system, title: part.title)
            if let group = groups[key] {
                groups[key] = (group.count + 1, group.common.intersection(part.tags))
            } else {
                groups[key] = (1, Set(part.tags))
            }
        }
        return zip(games, parts).map { game, part in
            var title = part.title
            let group = groups[TitleKey(system: game.system, title: title)]
            if let group, group.count > 1, let tag = part.tags.first(where: { !group.common.contains($0) }) {
                title += " (\(tag))"
            }
            return GameRecord(
                id: game.id,
                system: game.system,
                title: title,
                databaseName: game.databaseName,
                fileURL: game.fileURL,
                kind: game.kind,
                fileSize: game.fileSize,
                artStatus: game.artStatus
            )
        }
    }

    private static func isRevision(_ tag: String) -> Bool {
        tag.wholeMatch(of: /Rev [A-Za-z0-9]+|[vV]\d+(?:\.\d+)*/) != nil
    }

    private static func outranks(_ revision: String?, _ other: String?) -> Bool {
        guard let revision else { return false }
        guard let other else { return true }
        return revision.localizedStandardCompare(other) == .orderedDescending
    }

    private static func parts(of game: GameRecord) -> Parts {
        if let databaseName = game.databaseName {
            return parts(ofDatabaseName: databaseName)
        }
        return parts(ofFileName: game.fileURL.lastPathComponent)
    }

    static func parts(ofDatabaseName text: String) -> Parts {
        var kept = ""
        var tags: [String] = []
        var depth = 0
        var tagStart = text.startIndex
        var unclosedStart = text.startIndex

        for index in text.indices {
            let character = text[index]
            if character == "(" || character == "[" {
                if depth == 0 {
                    unclosedStart = index
                    tagStart = text.index(after: index)
                }
                depth += 1
            } else if character == ")" || character == "]", depth > 0 {
                depth -= 1
                if depth == 0 {
                    tags.append(String(text[tagStart..<index]))
                }
            } else if depth == 0 {
                kept.append(character)
            }
        }
        if depth > 0 {
            kept += text[unclosedStart...]
        }

        let title = kept.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if title.isEmpty {
            return Parts(title: text.split(whereSeparator: \.isWhitespace).joined(separator: " "), tags: [])
        }
        return Parts(title: title, tags: tags)
    }
}
