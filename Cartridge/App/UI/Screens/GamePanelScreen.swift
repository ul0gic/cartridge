import SwiftUI

struct GamePanelScreen: View {
    let model: AppModel
    let id: GameID

    var body: some View {
        if let game = model.game(for: id) {
            PanelLayout(model: model, game: game)
        } else {
            Palette.background.ignoresSafeArea()
        }
    }
}

private struct PanelLayout: View {
    let model: AppModel
    let game: GameRecord

    @State private var art = TileArt.loading
    @State private var colors = AmbientColors.brand
    @State private var source = BackdropSource.collage
    @State private var showsMoment = false
    @State private var latestSave: Date?
    @State private var setsUpDrive = false

    var body: some View {
        let insert = model.insert.flatMap { $0.game == game.id ? $0 : nil }
        TimelineView(.animation(paused: insert == nil)) { context in
            let frame = insert.map { InsertFrame(milliseconds: $0.milliseconds(at: context.date), system: game.system) }
            scaffold(frame: frame)
                .overlay {
                    if let insert, let frame {
                        InsertCurtain(
                            insert: insert,
                            frame: frame,
                            title: game.title,
                            system: game.system,
                            isMoment: model.hasResumeState(for: game),
                            glyphs: model.chrome.glyphs,
                            date: context.date
                        )
                    }
                }
        }
        .task(id: game.artStatus) {
            art = await model.tileArt(for: game)
            colors = await model.ambientColors(for: game)
        }
        .task(id: game.id) {
            latestSave = model.latestSaveStateAt(for: game)
            setsUpDrive = model.setsUpXboxDrive(for: game)
            if let frame = await model.resumeFrame(for: game) {
                source = .screenshot(frame)
                showsMoment = true
            } else {
                source = await model.backdrop(for: game)
                showsMoment = false
            }
        }
    }

    private func scaffold(frame: InsertFrame?) -> some View {
        let content = model.panelContent(for: game)
        let resumes = model.hasResumeState(for: game)
        return ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: Self.hints(
                for: content,
                buttons: (resumes ? ["Resume", "Start Fresh"] : ["Play"]) + (latestSave == nil ? [] : ["Saves"]),
                focused: model.focusedButton,
                isFavorite: model.isFavorite(game)
            ),
            console: game.system,
            chromeOpacity: 1 - (frame?.chrome ?? 0),
            backdrop: { backdrop(frame: frame) },
            content: {
                GeometryReader { proxy in
                    let alignment: Alignment = resumes ? .bottomLeading : .leading
                    ZStack(alignment: alignment) {
                        PanelCaseStage(
                            controller: model.dependencies.controller,
                            game: game,
                            art: art,
                            isMoment: resumes,
                            canvas: proxy.size,
                            frame: frame
                        )
                        PanelBody(
                            model: model,
                            game: game,
                            content: content,
                            resumes: resumes,
                            metadata: model.metadata(for: game),
                            latestSave: latestSave,
                            setsUpDrive: setsUpDrive,
                            press: frame?.press ?? 1
                        )
                        .opacity(1 - (frame?.chrome ?? 0))
                        .offset(x: -Layout.panelInsertChromeShift * (frame?.chrome ?? 0))
                        .frame(width: Layout.panelBodyWidth, alignment: .leading)
                        .padding(.leading, Layout.marginX)
                        .padding(.top, resumes ? 0 : model.chrome.safeTop + Space.n2 + Layout.topbarHeight)
                        .padding(.bottom, resumes ? Layout.panelMomentBottom : Layout.hintbarHeight)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
                }
                Color.black
                    .opacity(model.isFadingToBlack ? 1 : 0)
                    .allowsHitTesting(false)
            }
        )
    }

    private func backdrop(frame: InsertFrame?) -> some View {
        ZStack {
            CinematicBackdrop(
                source: source,
                style: showsMoment ? .moment(game.system) : .detail,
                heightFraction: 1
            )
            ZStack {
                AmbientBackdrop(colors: colors, layout: .open, drawsBase: false, intensity: 0.4)
                ConsoleFrame(
                    system: game.system,
                    showsArtwork: false,
                    intensity: Layout.consoleFrameDetailStrength
                )
            }
            .opacity(showsMoment ? 0 : 1)
            .animation(
                Motion.easeInOut(Motion.ambient).delay(Motion.ambientDelay.seconds),
                value: showsMoment
            )
            if let frame {
                Color.black.opacity(game.system.insertSchedule.dim * frame.dim)
            }
        }
    }

    private static func hints(
        for content: PanelContent,
        buttons: [String],
        focused: Int,
        isFavorite: Bool
    ) -> [Hint] {
        let favorite = Hint(kind: .secondary, label: isFavorite ? "Unfavorite" : "Favorite")
        return switch content {
        case .play where buttons.count > 1:
            [
                Hint(kind: .game, label: "Choose"),
                Hint(kind: .confirm, label: buttons[min(focused, buttons.count - 1)]),
                favorite,
                Hint(kind: .back, label: "Library"),
            ]
        case .play, .biosReady, .xboxFirmwareReady:
            [
                Hint(kind: .confirm, label: buttons[0]),
                favorite,
                Hint(kind: .back, label: "Library"),
            ]
        case .slots(isStarting: false):
            [
                Hint(kind: .game, label: "Choose"),
                Hint(kind: .confirm, label: "Start"),
                Hint(kind: .back, label: "Back"),
            ]
        case .starting, .slots:
            [Hint(kind: .back, label: "Cancel")]
        case .failed:
            [Hint(kind: .confirm, label: "OK")]
        case .biosNeeded:
            [
                Hint(kind: .move, label: "Move"),
                Hint(kind: .confirm, label: "Select"),
                Hint(kind: .back, label: "Library"),
            ]
        case .xboxFirmwareNeeded:
            [
                Hint(kind: .confirm, label: "Choose Folder"),
                Hint(kind: .back, label: "Library"),
            ]
        }
    }
}

private struct PanelBody: View {
    let model: AppModel
    let game: GameRecord
    let content: PanelContent
    let resumes: Bool
    let metadata: GameMetadata?
    let latestSave: Date?
    let setsUpDrive: Bool
    let press: Double

    private var record: PlayRecord? {
        model.playRecord(for: game)
    }

    private var showsSummary: Bool {
        switch content {
        case .play, .starting, .biosReady, .slots: !resumes
        case .failed, .biosNeeded, .xboxFirmwareNeeded, .xboxFirmwareReady: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.n2) {
                SystemBadge(name: game.system.displayName)
                FavoriteBadge(isFavorite: model.isFavorite(game))
            }
            .padding(.bottom, Space.n4)
            Text(game.title)
                .typeStyle(.title(long: game.title.isLongTitle, large: true))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 6)
                .padding(.bottom, resumes ? Space.n4 : Space.n5)
            if content != .failed, !content.isXboxFirmware, !resumes {
                MetadataChips(metadata: metadata)
                    .padding(.bottom, Space.n6)
            }
            if showsSummary, let summary = metadata?.summary {
                Text(summary)
                    .typeStyle(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(4)
                    .frame(maxWidth: Layout.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.n5)
            }
            switch content {
            case .play, .starting:
                PlayContent(
                    model: model,
                    resumes: resumes,
                    record: record,
                    metadata: metadata,
                    latestSave: latestSave,
                    setsUpDrive: setsUpDrive,
                    isStarting: content == .starting,
                    press: press
                )
            case .slots(let isStarting):
                if resumes, let record, let line = PlayedLine(record: record) {
                    line
                        .padding(.bottom, Space.n6)
                }
                PanelSlotPicker(
                    game: game,
                    slots: model.panelSlots(for: game),
                    highlighted: model.highlightedPanelSlot(for: game),
                    isStarting: isStarting,
                    press: press
                )
            case .failed:
                FailedContent(game: game)
            case .biosNeeded:
                BIOSContent(model: model)
            case .biosReady:
                BIOSReadyContent(model: model, game: game, record: record)
            case .xboxFirmwareNeeded:
                XboxFirmwareNeededContent(model: model)
            case .xboxFirmwareReady:
                XboxFirmwareReadyContent(model: model)
            }
        }
    }
}

private struct PlayContent: View {
    let model: AppModel
    let resumes: Bool
    let record: PlayRecord?
    let metadata: GameMetadata?
    let latestSave: Date?
    let setsUpDrive: Bool
    let isStarting: Bool
    let press: Double

    var body: some View {
        if resumes {
            if let record, let line = PlayedLine(record: record) {
                line
            }
            ButtonGroup {
                ActionButton(
                    glyph: "play.fill",
                    label: isBusy(0) ? "Starting…" : "Resume",
                    isHighlighted: model.focusedButton == 0,
                    isBusy: isBusy(0)
                )
                .scaleEffect(model.focusedButton == 0 ? press : 1)
                ActionButton(
                    glyph: "power",
                    label: isBusy(1) ? "Starting…" : "Start Fresh",
                    isHighlighted: model.focusedButton == 1,
                    isBusy: isBusy(1)
                )
                .scaleEffect(model.focusedButton == 1 ? press : 1)
                if latestSave != nil {
                    saveStatesButton(2)
                }
            }
            .padding(.top, Space.n6)
            Text("Starts from power-on with your in-game saves. When you quit, this becomes your resume point.")
                .typeStyle(.caption)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: Layout.panelNoteWidth, minHeight: Layout.panelNoteMinHeight, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.n4)
                .opacity(model.focusedButton == 1 ? 1 : 0)
                .accessibilityHidden(model.focusedButton != 1)
        } else {
            ButtonGroup {
                ActionButton(
                    glyph: "play.fill",
                    label: isStarting ? "Starting…" : "Play",
                    isHighlighted: isStarting || model.focusedButton == 0,
                    isBusy: isStarting
                )
                .scaleEffect(isStarting || model.focusedButton == 0 ? press : 1)
                if latestSave != nil {
                    saveStatesButton(1)
                }
            }
            PanelFacts(record: record, metadata: metadata, latestSave: latestSave, setsUpDrive: setsUpDrive)
                .padding(.top, Space.n5)
        }
    }

    private func saveStatesButton(_ button: Int) -> some View {
        ActionButton(
            glyph: nil,
            label: "Saves",
            isHighlighted: !isStarting && model.focusedButton == button
        )
        .scaleEffect(!isStarting && model.focusedButton == button ? press : 1)
    }

    private func isBusy(_ button: Int) -> Bool {
        isStarting && model.focusedButton == button
    }
}

private struct PanelFacts: View {
    let record: PlayRecord?
    let metadata: GameMetadata?
    let latestSave: Date?
    let setsUpDrive: Bool

    private var isUnplayed: Bool {
        record?.lastPlayedAt == nil && record?.resumeStateAt == nil && record?.batterySaveAt == nil
            && latestSave == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.n3) {
            if let developer = metadata?.developer {
                FactLine(glyph: "hammer", lead: "Developer", rest: developer)
            }
            if let publisher = metadata?.publisher, publisher != metadata?.developer {
                FactLine(glyph: "shippingbox", lead: "Publisher", rest: publisher)
            }
            if let record, let line = PlayedLine(record: record) {
                HStack(spacing: Space.n3) {
                    GlyphLabel(symbol: "clock")
                    line
                }
                .accessibilityElement(children: .combine)
            }
            if let date = record?.batterySaveAt {
                FactLine(glyph: "memorychip", lead: "Battery save", rest: "updated \(DisplayDate.text(date))")
            }
            if let date = latestSave {
                FactLine(
                    glyph: "square.and.arrow.down",
                    lead: "Latest save state",
                    rest: "from \(DisplayDate.text(date))"
                )
            }
            if isUnplayed {
                FactLine(glyph: "minus.circle", lead: "Not played yet", rest: "")
            }
            if setsUpDrive {
                FactLine(
                    glyph: "internaldrive",
                    lead: "First start",
                    rest: "sets up this game’s Xbox drive and can take up to 30 seconds"
                )
            }
        }
    }
}

private struct FailedContent: View {
    let game: GameRecord

    var body: some View {
        MessageHead(kind: .danger, text: "\(game.title) didn’t start")
        MessageParagraph(
            text: "Cartridge couldn’t read this file as a \(game.system.displayName) game. "
                + "It may be damaged or incomplete. Other games aren’t affected."
        )
        .padding(.bottom, Space.n5)
        ActionButton(glyph: nil, label: "OK", isHighlighted: true)
    }
}

private struct BIOSContent: View {
    let model: AppModel

    private var biosChips: some View {
        ForEach(BIOSRegion.allCases, id: \.self) { region in
            FileChip(name: region.rawValue, region: region.displayName)
        }
    }

    var body: some View {
        MessageHead(kind: .warning, text: "PS1 BIOS needed")
        MessageParagraph(
            text: "PS1 games run best with the system file from your own console. Cartridge accepts any one of these:"
        )
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.n3) { biosChips }
            VStack(alignment: .leading, spacing: Space.n3) { biosChips }
        }
        .padding(.top, Space.n4)
        .padding(.bottom, Space.n6)
        if let result = model.biosResult, let failure = BIOSFailureText(result) {
            InlineResult(kind: .warning, lead: failure.lead, rest: failure.rest)
                .padding(.bottom, Space.n5)
        }
        ButtonGroup {
            ActionButton(
                glyph: "folder",
                label: "Choose Folder…",
                note: "Opens a Finder window. Pick the folder with the trackpad or keyboard.",
                isHighlighted: model.focusedButton == 0
            )
            ActionButton(
                glyph: "play.fill",
                label: "Play Anyway",
                note: "Uses a built-in replacement. Some games won’t start or will have glitches.",
                isHighlighted: model.focusedButton == 1
            )
        }
    }
}

private struct BIOSReadyContent: View {
    let model: AppModel
    let game: GameRecord
    let record: PlayRecord?

    var body: some View {
        MessageHead(kind: .success, text: "PS1 BIOS ready")
        // swiftlint:disable:next pattern_matching_keywords - swiftformat patternlet inline conflict
        if case .imported(let regions, let folderName) = model.biosResult {
            MessageParagraph(
                text: "Found \(regions.map(\.displayName).sentenceList) in \(folderName). "
                    + "Cartridge keeps its own copy, so the original files stay where they are."
            )
            .padding(.bottom, Space.n5)
        }
        ActionButton(glyph: "play.fill", label: "Play", isHighlighted: true)
    }
}

struct BIOSFailureText {
    let lead: String
    let rest: String

    init?(_ result: BIOSImportResult) {
        switch result {
        case .imported:
            return nil
        // swiftlint:disable:next pattern_matching_keywords - swiftformat patternlet inline conflict
        case .noneFound(let fileCount, let folderName):
            lead = "No PS1 BIOS in \(folderName)."
            rest = "None of its \(fileCount.formatted()) files matches the three above. "
                + "Try the folder where you keep them, such as an old emulator’s BIOS folder."
        // swiftlint:disable:next pattern_matching_keywords - swiftformat patternlet inline conflict
        case .badChecksum(let fileName, let folderName):
            lead = "\(fileName) in \(folderName) isn’t a known good copy."
            rest = "Cartridge needs an exact dump of the file from a console."
        }
    }
}
