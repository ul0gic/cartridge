import SwiftUI

struct AboutScreen: View {
    let model: AppModel

    @State private var credits = AboutCredits()

    var body: some View {
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: [Hint(kind: .row, label: "Scroll"), Hint(kind: .back, label: "Back")],
            backdrop: { EmptyView() },
            content: {
                HStack(alignment: .top, spacing: Space.n7) {
                    AboutSummary()
                        .frame(width: Layout.settingsLeftWidth, alignment: .leading)
                    CreditsList(credits: credits, scroll: model.aboutScroll)
                }
                .padding(.horizontal, Layout.marginX)
                .padding(.top, model.chrome.safeTop + Space.n2 + Layout.topbarHeight + Space.n6)
                .padding(.bottom, Layout.hintbarHeight)
            }
        )
        .task { credits = await AboutCredits.load() }
    }
}

private struct AboutSummary: View {
    private static let summary = [
        "Plays NES, SNES, Genesis, N64, PS1 and Xbox games you own.",
        "Cartridge reads your ROM folder and never changes it.",
    ].joined(separator: " ")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppIconImage(size: Layout.welcomeIcon)
                .padding(.bottom, Space.n5)
            Text("About Cartridge")
                .typeStyle(.titleL)
                .foregroundStyle(Palette.textPrimary)
                .padding(.bottom, Space.n3)
            if let version = AppVersion.line {
                Text("Version \(version)")
                    .typeStyle(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, Space.n3)
            }
            Text(Self.summary)
                .typeStyle(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CreditsList: View {
    let credits: AboutCredits
    let scroll: AboutScrollRequest

    @State private var position = ScrollPosition()
    @State private var offset: CGFloat = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CreditSection(title: "Emulation", rows: credits.emulation)
                CreditSection(
                    title: "Game titles",
                    rows: [
                        CreditRow(label: "libretro-database", value: "No-Intro and Redump data, CC BY-SA 4.0"),
                        AboutCredits.cheatData,
                    ]
                )
                CreditSection(title: "Box art", rows: [Self.boxArt])
                Text("Full license texts")
                    .typeStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, Space.n6)
                    .padding(.bottom, Space.n3)
                    .accessibilityAddTraits(.isHeader)
                ForEach(credits.licenses) { license in
                    CreditEntry(label: license.name) {
                        LazyVStack(alignment: .leading, spacing: Space.n3) {
                            ForEach(Array(license.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, Space.n9)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { offset = $1 })
        .onChange(of: scroll) {
            position.scrollTo(y: max(0, offset + CGFloat(scroll.direction) * Self.lineHeight))
        }
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Space.n8)
            }
        }
    }

    private static let boxArt = CreditRow(
        label: "libretro thumbnails",
        value: "Fetched from thumbnails.libretro.com when a game first appears. Art belongs to its publishers."
    )

    private static var lineHeight: CGFloat {
        TypeStyle.body.size * TypeStyle.body.leading
    }
}

private struct CreditSection: View {
    let title: String
    let rows: [CreditRow]

    var body: some View {
        Text(title)
            .typeStyle(.headline)
            .foregroundStyle(Palette.textPrimary)
            .padding(.top, Space.n6)
            .padding(.bottom, Space.n3)
            .accessibilityAddTraits(.isHeader)
        ForEach(rows) { row in
            CreditEntry(label: row.label) {
                Text(row.value)
            }
        }
    }
}

private struct CreditEntry<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .typeStyle(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Layout.creditLabelWidth, alignment: .leading)
            value
                .typeStyle(.body)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.n3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.controlStroke).frame(height: Layout.strokeHair)
        }
        .accessibilityElement(children: .combine)
    }
}
