import Foundation

enum CodePadKey: Hashable {
    case character(Character)
    case space
    case delete
    case add
}

struct CodePad {
    private let characters: Set<Character>

    let rows: [[CodePadKey]]
    private(set) var row = 0
    private(set) var column = 0
    private(set) var code = ""

    init(system: GameSystem) {
        let characters = CheatCodeFormat.padCharacters(for: system)
        let usesSpace = characters.contains(" ")
        self.characters = Set(characters)
        let letters = characters.filter { $0 != " " }.map(CodePadKey.character)
        var rows = stride(from: 0, to: letters.count, by: SearchState.padColumns).map {
            Array(letters[$0..<min($0 + SearchState.padColumns, letters.count)])
        }
        let wide: [CodePadKey] = (usesSpace ? [.space] : []) + [.delete, .add]
        rows += stride(from: 0, to: wide.count, by: 2).map { Array(wide[$0..<min($0 + 2, wide.count)]) }
        self.rows = rows
    }

    var highlightedKey: CodePadKey {
        rows[row][column]
    }

    mutating func move(_ direction: Direction) {
        switch direction {
        case .left:
            column = max(column - 1, 0)
        case .right:
            column = min(column + 1, rows[row].count - 1)
        case .up, .down:
            let target = row + (direction == .up ? -1 : 1)
            guard rows.indices.contains(target) else { return }
            let position = (Double(column) + 0.5) / Double(rows[row].count)
            column = min(Int(position * Double(rows[target].count)), rows[target].count - 1)
            row = target
        }
    }

    mutating func press(_ key: CodePadKey) {
        switch key {
        case .character(let character): append(character)
        case .space: append(" ")
        case .delete: eraseLast()
        case .add: break
        }
    }

    mutating func type(_ text: String) {
        for character in text.uppercased() {
            append(character)
        }
    }

    mutating func eraseLast() {
        if !code.isEmpty {
            code.removeLast()
        }
    }

    private mutating func append(_ character: Character) {
        guard characters.contains(character), code.count < CheatCodeFormat.maxLength else { return }
        if character == " ", code.isEmpty || code.last == " " {
            return
        }
        code.append(character)
    }
}
