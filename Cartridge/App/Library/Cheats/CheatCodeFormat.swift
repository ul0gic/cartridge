import Foundation

enum CheatCodeFormat {
    static let maxLength = 254
    static let genesisCodeLimit = 150

    private struct PieceSet {
        let genieAlphabet: Set<Character>
        let patterns: [String]
    }

    private static let hex = Set("0123456789ABCDEF")

    private static let nesPieces = PieceSet(
        genieAlphabet: Set("APZLGITYEOXUKSVN"),
        patterns: ["@@@@@@", "@@@@@@@@", "########", "####:##", "####?##:##"]
    )

    private static let snesPieces = PieceSet(genieAlphabet: [], patterns: ["####-####", "########"])

    private static let genesisPieces = PieceSet(
        genieAlphabet: Set("ABCDEFGHJKLMNPRSTVWXYZ0123456789"),
        patterns: ["@@@@-@@@@", "######:####"]
    )

    static func formats(for system: GameSystem) -> [CheatFormat] {
        switch system {
        case .nes:
            [
                CheatFormat(name: "Game Genie", pattern: "XXXXXX or XXXXXXXX"),
                CheatFormat(name: "Pro Action Rocky", pattern: "XXXXXXXX"),
                CheatFormat(name: "Raw address", pattern: "AAAA:VV"),
                CheatFormat(name: "Raw address with compare", pattern: "AAAA?CC:VV"),
            ]
        case .snes:
            [
                CheatFormat(name: "Game Genie", pattern: "XXXX-XXXX"),
                CheatFormat(name: "Pro Action Replay", pattern: "XXXXXXXX"),
            ]
        case .genesis:
            [
                CheatFormat(name: "Game Genie", pattern: "XXXX-XXXX"),
                CheatFormat(name: "Action Replay", pattern: "AAAAAA:VVVV"),
            ]
        case .ps1:
            [CheatFormat(name: "GameShark / Game Buster / Xploder", pattern: "AAAAAAAA VVVV")]
        case .n64:
            [CheatFormat(name: "GameShark", pattern: "AAAAAAAA VVVV")]
        case .xbox:
            []
        }
    }

    static func padCharacters(for system: GameSystem) -> [Character] {
        switch system {
        case .nes: Array("APZLGITYEOXUKSVN0123456789BCDF:?+")
        case .snes: Array("0123456789ABCDEF-+")
        case .genesis: Array("ABCDEFGHJKLMNPRSTVWXYZ0123456789-:+")
        case .ps1, .n64: Array("0123456789ABCDEF +")
        case .xbox: []
        }
    }

    static func normalize(_ code: String, for system: GameSystem) -> Result<String, CheatCodeError> {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.isEmpty {
            return .failure(.empty)
        }
        if text.count > maxLength {
            return .failure(.tooLong)
        }
        switch system {
        case .nes: return normalizePieces(text, pieceSet: nesPieces)
        case .snes: return normalizePieces(text, pieceSet: snesPieces)
        case .genesis: return normalizePieces(text, pieceSet: genesisPieces)
        case .ps1, .n64: return normalizePairs(text)
        case .xbox: return .failure(.noFormat)
        }
    }

    static func codeCount(_ normalized: String, for system: GameSystem) -> Int {
        switch system {
        case .nes, .snes, .genesis: normalized.split(separator: "+").count
        case .ps1, .n64: runs(of: normalized).count / 2
        case .xbox: 0
        }
    }

    private static func normalizePieces(_ text: String, pieceSet: PieceSet) -> Result<String, CheatCodeError> {
        let pieces = text.split(separator: "+", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard pieces.allSatisfy({ piece in pieceSet.patterns.contains { matches(piece, pattern: $0, in: pieceSet) } })
        else { return .failure(.noFormat) }
        return .success(pieces.joined(separator: "+"))
    }

    private static func normalizePairs(_ text: String) -> Result<String, CheatCodeError> {
        let runs = runs(of: text)
        guard runs.count >= 2, runs.count.isMultiple(of: 2) else { return .failure(.noFormat) }
        var pairs: [String] = []
        for start in stride(from: 0, to: runs.count, by: 2) {
            let address = runs[start]
            let value = runs[start + 1]
            guard address.count == 8, value.count == 4,
                  address.allSatisfy(hex.contains), value.allSatisfy(hex.contains)
            else { return .failure(.noFormat) }
            pairs.append("\(address) \(value)")
        }
        return .success(pairs.joined(separator: "+"))
    }

    private static func runs(of text: String) -> [Substring] {
        text.split { $0 == "+" || $0.isWhitespace }
    }

    private static func matches(_ piece: String, pattern: String, in pieceSet: PieceSet) -> Bool {
        piece.count == pattern.count && zip(piece, pattern).allSatisfy { character, symbol in
            switch symbol {
            case "#": hex.contains(character)
            case "@": pieceSet.genieAlphabet.contains(character)
            default: character == symbol
            }
        }
    }
}
