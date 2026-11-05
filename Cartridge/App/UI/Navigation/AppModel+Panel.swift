import Foundation

enum PanelContent: Equatable {
    case play
    case slots(isStarting: Bool)
    case starting
    case failed
    case biosNeeded
    case biosReady
    case xboxFirmwareNeeded
    case xboxFirmwareReady

    var isXboxFirmware: Bool {
        self == .xboxFirmwareNeeded || self == .xboxFirmwareReady
    }
}

struct PanelSlot: Equatable {
    let record: SlotRecord
    let thumbnail: URL?
}

struct PanelSlots: Equatable {
    let game: GameID
    let slots: [PanelSlot]
}

extension AppModel {
    func game(for id: GameID) -> GameRecord? {
        dependencies.library.index?.games.first { $0.id == id }
    }

    func playRecord(for game: GameRecord) -> PlayRecord? {
        dependencies.library.playRecord(for: game.id)
    }

    func hasResumeState(for game: GameRecord) -> Bool {
        playRecord(for: game)?.resumeStateAt != nil
    }

    func latestSaveStateAt(for game: GameRecord) -> Date? {
        dependencies.slots.newestSavedAt(for: game.id, legacyManualStateAt: playRecord(for: game)?.manualStateAt)
    }

    func panelSlots(for game: GameRecord) -> [PanelSlot] {
        guard case .slots(let picker) = panelPhase, picker.game == game.id else { return [] }
        return picker.slots
    }

    func highlightedPanelSlot(for game: GameRecord) -> SlotNumber? {
        if case .slot(let slot) = session?.start {
            return slot
        }
        let slots = panelSlots(for: game)
        return slots.indices.contains(focusedButton) ? slots[focusedButton].record.number : nil
    }

    var isPickingSlot: Bool {
        if case .slots = panelPhase {
            return true
        }
        return false
    }

    func panelContent(for game: GameRecord) -> PanelContent {
        switch panelPhase {
        case .starting:
            return .starting
        case .failed:
            return .failed
        case .slots(let picker) where picker.game == game.id:
            return .slots(isStarting: session != nil)
        case .idle, .slots:
            break
        }
        switch game.system {
        case .ps1:
            if case .imported = biosResult, dependencies.bios.isReady {
                return .biosReady
            }
            return dependencies.bios.isReady ? .play : .biosNeeded
        case .xbox:
            guard dependencies.xboxFirmware.isReady else { return .xboxFirmwareNeeded }
            return xboxFirmwareImport?.imported.isEmpty == false ? .xboxFirmwareReady : .play
        case .nes, .snes, .genesis, .n64:
            return .play
        }
    }

    func setsUpXboxDrive(for game: GameRecord) -> Bool {
        game.system == .xbox && !FileManager.default.fileExists(atPath: StoragePaths.xboxGameDrive(for: game.id).path)
    }

    func handlePanel(_ event: NavigationEvent, id: GameID) {
        guard let game = game(for: id) else {
            resetSlotPicker()
            show(returnRoute)
            return
        }
        guard !isFadingToBlack, insert?.isCancellable ?? true else { return }
        let content = panelContent(for: game)
        if content == .starting || content == .slots(isStarting: true) {
            if event.action == .back {
                cancelStart()
            }
            return
        }
        if event.action == .secondary {
            if content == .play || content == .biosReady || content == .xboxFirmwareReady {
                toggleFavorite(game)
            }
            return
        }
        if let button = confirmButton(event, count: buttonCount(content, game: game)) {
            activatePanel(content, button: button, game: game)
        } else if event.action == .back {
            leavePanel(content, game: game)
        }
    }

    private func leavePanel(_ content: PanelContent, game: GameRecord) {
        switch content {
        case .failed:
            panelPhase = .idle
        case .slots:
            closeSlotPicker(for: game)
        case .play, .starting, .biosNeeded, .biosReady, .xboxFirmwareNeeded, .xboxFirmwareReady:
            show(returnRoute)
        }
    }

    private func saveStatesButton(for game: GameRecord) -> Int {
        hasResumeState(for: game) ? 2 : 1
    }

    private func buttonCount(_ content: PanelContent, game: GameRecord) -> Int {
        switch content {
        case .biosNeeded: 2
        case .play: (hasResumeState(for: game) ? 2 : 1) + (latestSaveStateAt(for: game) == nil ? 0 : 1)
        case .slots: panelSlots(for: game).count
        case .biosReady, .xboxFirmwareNeeded, .xboxFirmwareReady, .starting, .failed: 1
        }
    }

    private func activatePanel(_ content: PanelContent, button: Int, game: GameRecord) {
        switch content {
        case .play:
            if button == saveStatesButton(for: game) {
                openSlotPicker(for: game)
            } else {
                startPlay(game, withoutBIOS: false, start: button == 1 ? .fresh : .resume)
            }
        case .slots:
            startFromSlot(button, game: game)
        case .biosReady, .xboxFirmwareReady:
            startPlay(game, withoutBIOS: false, start: .resume)
        case .xboxFirmwareNeeded:
            chooseXboxFirmwareFolder()
        case .biosNeeded:
            if button == 0 {
                chooseBIOSFolder()
            } else {
                startPlay(game, withoutBIOS: true, start: .resume)
            }
        case .failed:
            panelPhase = .idle
        case .starting:
            break
        }
    }

    private func startFromSlot(_ button: Int, game: GameRecord) {
        let slots = panelSlots(for: game)
        guard slots.indices.contains(button) else { return }
        startPlay(game, withoutBIOS: false, start: .slot(slots[button].record.number))
        if session != nil {
            focusedButton = saveStatesButton(for: game)
        }
    }

    private func openSlotPicker(for game: GameRecord) {
        let store = dependencies.slots
        let records = store.slots(for: game.id, legacyManualStateAt: playRecord(for: game)?.manualStateAt).values
            .sorted { ($0.savedAt, $1.number) > ($1.savedAt, $0.number) }
        guard !records.isEmpty else { return }
        let slots = records.map { PanelSlot(record: $0, thumbnail: store.thumbnailURL($0.number, for: game.id)) }
        panelPhase = .slots(PanelSlots(game: game.id, slots: slots))
        focusedButton = 0
    }

    func resetSlotPicker() {
        guard isPickingSlot, session == nil else { return }
        panelPhase = .idle
    }

    private func closeSlotPicker(for game: GameRecord) {
        panelPhase = .idle
        focusedButton = saveStatesButton(for: game)
    }
}
