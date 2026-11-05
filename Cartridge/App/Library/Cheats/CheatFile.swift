import Foundation

enum CheatFile {
    struct Entry {
        let index: Int
        let description: String
        let code: String
    }

    enum ReadError: Error {
        case unreadable
        case tooLarge
        case tooManyEntries
    }

    static let maxBytes = 8 * 1024 * 1024
    static let maxEntries = 50000

    private struct Partial {
        var description: String?
        var code: String?
        var usesRetroHandler = false
    }

    static func entries(at url: URL) throws(ReadError) -> [Entry] {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        } catch {
            throw .unreadable
        }
        guard data.count <= maxBytes else { throw .tooLarge }
        guard let text = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) else {
            throw .unreadable
        }
        return try entries(in: text)
    }

    private static func entries(in text: String) throws(ReadError) -> [Entry] {
        var declared = 0
        var partials: [Int: Partial] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = extractValue(line[line.index(after: equals)...])
            if key == "cheats" {
                declared = Int(value) ?? 0
            } else if let (index, field) = split(key), index < maxEntries {
                switch field {
                case "desc": partials[index, default: Partial()].description = value
                case "code": partials[index, default: Partial()].code = value
                case "handler": partials[index, default: Partial()].usesRetroHandler = value == "1" || value == "true"
                default: break
                }
            }
        }
        guard declared <= maxEntries else { throw .tooManyEntries }
        return partials.keys.sorted().compactMap { index in
            guard index < declared, let partial = partials[index], !partial.usesRetroHandler,
                  let description = partial.description, !description.isEmpty, let code = partial.code
            else { return nil }
            return Entry(index: index, description: description, code: code)
        }
    }

    private static func split(_ key: String) -> (index: Int, field: Substring)? {
        guard key.hasPrefix("cheat") else { return nil }
        let rest = key.dropFirst(5)
        let digits = rest.prefix { ("0"..."9").contains($0) }
        guard !digits.isEmpty, let index = Int(digits) else { return nil }
        let field = rest.dropFirst(digits.count)
        guard field.first == "_" else { return nil }
        return (index, field.dropFirst())
    }

    private static func extractValue(_ text: Substring) -> String {
        let trimmed = text.drop { $0 == " " || $0 == "\t" }
        if trimmed.first == "\"" {
            let body = trimmed.dropFirst()
            return String(body.prefix { $0 != "\"" })
        }
        return String(trimmed.prefix { !$0.isWhitespace })
    }
}
