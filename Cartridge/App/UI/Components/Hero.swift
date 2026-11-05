import SwiftUI

enum HeroState: Equatable {
    case resume(String)
    case unplayed
}

struct Hero: View {
    let system: String
    let title: String
    let metadata: GameMetadata?
    let state: HeroState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SystemBadge(name: system)
                .padding(.bottom, Space.n4)
            Text(title)
                .typeStyle(.title(long: title.isLongTitle, large: true))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(Clamp.heroTitle)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 6)
            HeroFacts(metadata: metadata)
                .padding(.top, Space.n4)
            stateLine
                .padding(.top, Space.n4)
        }
        .frame(maxWidth: Layout.heroTextMax, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([title, system, MetadataText.line(metadata)].compactMap(\.self)
                .joined(separator: ", ")))
    }

    private var stateLine: some View {
        HStack(spacing: Space.n2) {
            switch state {
            case .resume(let date):
                GlyphLabel(symbol: "bookmark.fill", color: Palette.resumeMark)
                Text("\(Text("Resume").fontWeight(.semibold).foregroundStyle(Palette.textPrimary)) from \(date)")
            case .unplayed:
                GlyphLabel(symbol: "play.fill")
                Text("Not played yet")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .typeStyle(.body)
        .foregroundStyle(Palette.textSecondary)
    }
}

private struct HeroFacts: View {
    let metadata: GameMetadata?

    var body: some View {
        if let metadata {
            HStack(spacing: Space.n5) {
                if let year = metadata.year {
                    Text(String(year))
                        .fontWeight(.bold)
                        .foregroundStyle(Palette.textPrimary)
                }
                if let genre = metadata.genre {
                    Text(genre)
                }
                if let maker = metadata.developer ?? metadata.publisher {
                    Text(maker)
                }
                if let players = metadata.players {
                    Text(MetadataText.players(players))
                }
            }
            .typeStyle(.lede)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
        }
    }
}

struct ScanHero: View {
    let gamesFound: Int
    let filesChecked: Int
    let filesFound: Int
    let folderName: String
    let folderPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(gamesFound == 1 ? "1 game found" : "\(gamesFound.formatted()) games found")
                .typeStyle(.titleL)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            HStack(spacing: Space.n4) {
                ProgressBar(fraction: filesFound == 0 ? 0 : Double(filesChecked) / Double(filesFound))
                Spinner()
                Text("Checked \(filesChecked.formatted()) of \(filesFound.formatted()) files")
                    .typeStyle(.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, Space.n3)
            ScanFolderLine(name: folderName, path: folderPath)
                .padding(.top, Space.n3)
        }
        .frame(maxWidth: Layout.heroTextMax, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
