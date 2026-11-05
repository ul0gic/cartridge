import Foundation

enum DisplayDate {
    static func text(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        let day: String
        switch days {
        case ..<0, 0: day = "today"
        case 1: day = "yesterday"
        case 2...6: day = date.formatted(.dateTime.weekday(.wide))
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            day = sameYear
                ? date.formatted(.dateTime.month(.wide).day())
                : date.formatted(.dateTime.month(.wide).day().year())
        }
        return "\(day), \(time)"
    }
}

extension [String] {
    var sentenceList: String {
        guard count > 1, let last else { return first ?? "" }
        return "\(dropLast().joined(separator: ", ")) and \(last)"
    }
}
