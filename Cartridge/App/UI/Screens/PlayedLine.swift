import SwiftUI

struct PlayedLine: View {
    private static let minuteSeconds: TimeInterval = 60
    private static let playedStyle = Duration.UnitsFormatStyle(
        allowedUnits: [.hours, .minutes],
        width: .narrow,
        fractionalPart: .hide(rounded: .toNearestOrEven)
    )

    private let text: Text

    init?(record: PlayRecord, now: Date = .now, calendar: Calendar = .current) {
        let played = record.playSeconds.flatMap { seconds in
            seconds < Self.minuteSeconds ? nil : Duration.seconds(seconds).formatted(Self.playedStyle)
        }
        let last = record.lastPlayedAt.map { Self.lastPlayed($0, now: now, calendar: calendar) }
        if let played, let last {
            text = Text("\(Self.lead("Played")) \(played) · \(Self.lead("Last played")) \(last)")
        } else if let played {
            text = Text("\(Self.lead("Played")) \(played)")
        } else if let last {
            text = Text("\(Self.lead("Last played")) \(last)")
        } else {
            return nil
        }
    }

    var body: some View {
        text
            .typeStyle(.body)
            .foregroundStyle(Palette.textSecondary)
            .shadow(color: .black.opacity(0.5), radius: 12, y: 2)
    }

    private static func lead(_ word: String) -> Text {
        Text(word).fontWeight(.semibold).foregroundStyle(Palette.textPrimary)
    }

    private static func lastPlayed(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ...0: return "today, \(date.formatted(date: .omitted, time: .shortened))"
        case 1: return "yesterday"
        case 2...6: return date.formatted(.dateTime.weekday(.wide))
        default:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
                ? date.formatted(.dateTime.month(.abbreviated).day())
                : date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}
