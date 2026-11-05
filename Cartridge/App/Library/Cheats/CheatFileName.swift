import Foundation

struct CheatFileName {
    private static let regionAliases: [String: String] = {
        let names = [
            "asia", "australia", "brazil", "canada", "china", "denmark", "europe", "finland", "france",
            "germany", "greece", "hong kong", "ireland", "israel", "italy", "japan", "korea", "latin america",
            "netherlands", "new zealand", "norway", "poland", "portugal", "russia", "scandinavia", "spain",
            "sweden", "taiwan", "uk", "usa", "world",
        ]
        var aliases = Dictionary(uniqueKeysWithValues: names.map { ($0, $0) })
        aliases["u"] = "usa"
        aliases["e"] = "europe"
        aliases["j"] = "japan"
        return aliases
    }()

    private static let devices: [String: String] = Dictionary(
        uniqueKeysWithValues: [
            "Game Genie", "Action Replay", "Pro Action Replay", "GameShark", "Game Buster", "Xploder", "Custom",
        ].map { ($0.lowercased(), $0) }
    )

    let baseTitle: String
    let regions: Set<String>
    let revision: String?
    let device: String?

    init(_ name: String) {
        baseTitle = TitleFormatter.parts(ofDatabaseName: name).title.lowercased()
        let groups = Self.groups(in: name)
        regions = groups.reduce(into: Set<String>()) { regions, group in
            let tokens = group.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let known = tokens.compactMap { Self.regionAliases[$0] }
            if !tokens.isEmpty, known.count == tokens.count {
                regions.formUnion(known)
            }
        }
        revision = groups.lazy.compactMap { group -> String? in
            let lowered = group.lowercased()
            guard lowered.hasPrefix("rev ") else { return nil }
            return lowered.dropFirst(4).trimmingCharacters(in: .whitespaces)
        }.first
        device = groups.last.flatMap { Self.devices[$0.lowercased()] }
    }

    func isCandidate(for game: CheatFileName) -> Bool {
        revision == game.revision && regionsOverlap(game)
    }

    private func regionsOverlap(_ game: CheatFileName) -> Bool {
        regions.contains("world") || !regions.isDisjoint(with: game.regions)
            || (game.regions.contains("world") && regions.contains("usa"))
    }

    private static func groups(in text: String) -> [String] {
        var groups: [String] = []
        var depth = 0
        var start = text.startIndex
        for index in text.indices {
            switch text[index] {
            case "(":
                if depth == 0 {
                    start = text.index(after: index)
                }
                depth += 1
            case ")" where depth > 0:
                depth -= 1
                if depth == 0 {
                    groups.append(String(text[start..<index]))
                }
            default:
                break
            }
        }
        return groups
    }
}
