import Foundation

enum HubFormat {
    static func date(_ date: Date) -> String {
        DisplayDate.text(date)
    }

    static func sentenceDate(_ date: Date) -> String {
        let text = DisplayDate.text(date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func milliseconds(since instant: ContinuousClock.Instant) -> Int {
        Int(instant.duration(to: .now).seconds * 1000)
    }

    static func fileSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func byteCount(_ bytes: Int) -> String {
        bytes.formatted(.number)
    }
}
