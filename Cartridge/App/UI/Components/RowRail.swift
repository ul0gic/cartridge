import SwiftUI

struct RailEntry: Identifiable, Equatable {
    let name: String
    let value: String
    let spokenValue: String
    var isNone = false

    var id: String {
        name
    }
}

struct RowRail: View {
    let entries: [RailEntry]
    let currentIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let isCurrent = index == currentIndex
                HStack {
                    Text(entry.name)
                    Spacer(minLength: Space.n4)
                    Text(entry.value)
                        .typeStyle(entry.isNone ? .meta : TypeStyle.rail.digits)
                }
                .typeStyle(.rail)
                .fontWeight(isCurrent ? .bold : .regular)
                .foregroundStyle(isCurrent ? Palette.textPrimary : Palette.textSecondary)
                .padding(.leading, Space.n4)
                .overlay(alignment: .leading) {
                    if isCurrent {
                        Capsule()
                            .fill(Palette.focusRing)
                            .frame(width: Layout.railMarkerWidth)
                            .padding(.vertical, Space.n1)
                    }
                }
            }
        }
        .padding(.vertical, Space.n2)
        .padding(.horizontal, Space.n4)
        .frame(width: Layout.railWidth)
        .plate()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Library rows")
        .accessibilityValue(spokenValue)
    }

    private var spokenValue: String {
        guard let currentIndex, entries.indices.contains(currentIndex) else { return "" }
        let entry = entries[currentIndex]
        return "Row \(currentIndex + 1) of \(entries.count), \(entry.name), \(entry.spokenValue)"
    }
}
