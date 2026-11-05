import Foundation
import Observation

enum SlotChoice {
    case load
    case saveHere
}

@MainActor
@Observable
final class SaveStatesPage: HubPage {
    private(set) var slots: [SlotNumber: SlotRecord] = [:]
    private(set) var thumbnails: [SlotNumber: URL] = [:]
    private(set) var highlighted = SlotNumber.all[0]
    private(set) var open: SlotNumber?
    private(set) var choice = SlotChoice.load
    private(set) var busy: SlotNumber?
    private(set) var savedSlot: SlotNumber?
    private(set) var busyLabel: String?

    let arming: Arming<SlotNumber>

    @ObservationIgnored private let context: HubContext

    var game: GameRecord {
        context.session.game
    }

    init(context: HubContext) {
        self.context = context
        arming = Arming(messages: context.messages)
        reload()
        if let newest = slots.values.max(by: { $0.savedAt < $1.savedAt }) {
            highlighted = newest.number
        }
    }

    var title: String {
        "Save States"
    }

    var subtitle: String {
        slots.isEmpty
            ? "\(game.title). No save states yet."
            : "\(game.title). \(slots.count) of \(SlotNumber.all.count) slots used."
    }

    var hints: [Hint] {
        if busy != nil {
            return []
        }
        return [
            Hint(kind: open == nil ? .row : .game, label: "Move"),
            Hint(kind: .confirm, label: "Select"),
            Hint(kind: .back, label: "Back"),
        ]
    }

    var counter: String? {
        nil
    }

    var showsOwnSavesNote: Bool {
        game.system == .xbox
    }

    var isJustSaved: Bool {
        savedSlot != nil && context.messages.current?.head == "State saved"
    }

    func handle(_ event: NavigationEvent) {
        guard busy == nil else { return }
        switch event.action {
        case .move(let direction):
            move(direction)
        case .confirm:
            confirm()
        case .back:
            goBack()
        case .pause, .options, .secondary, .section, .text, .erase:
            break
        }
    }

    private func move(_ direction: Direction) {
        switch direction {
        case .left, .right:
            guard open != nil else { return }
            let target: SlotChoice = direction == .left ? .load : .saveHere
            if target != choice {
                arming.disarm()
                choice = target
            }
        case .up, .down:
            guard let target = SlotNumber(highlighted.value + (direction == .up ? -1 : 1)) else { return }
            close()
            highlighted = target
        }
    }

    private func confirm() {
        guard let record = slots[highlighted] else {
            Task { await save(highlighted) }
            return
        }
        guard open == highlighted else {
            open = highlighted
            choice = .load
            return
        }
        switch choice {
        case .load:
            Task { await load(record) }
        case .saveHere:
            if arming.isArmed(highlighted) {
                arming.disarm()
                Task { await save(highlighted) }
            } else {
                arming.arm(
                    highlighted,
                    message: .warn(
                        "Replace slot \(highlighted.value)?",
                        "Its state from \(HubFormat.date(record.savedAt)) will be lost."
                    )
                )
            }
        }
    }

    private func goBack() {
        if open != nil {
            close()
        } else {
            context.exit(.main(highlight: .saveStates))
        }
    }

    private func close() {
        arming.disarm()
        open = nil
        choice = .load
    }

    private func reload() {
        let legacy = context.dependencies.library.playRecord(for: game.id)?.manualStateAt
        let store = context.dependencies.slots
        slots = store.slots(for: game.id, legacyManualStateAt: legacy)
        thumbnails = Dictionary(uniqueKeysWithValues: slots.keys.compactMap { slot in
            store.thumbnailURL(slot, for: game.id).map { (slot, $0) }
        })
    }

    private func save(_ slot: SlotNumber) async {
        busy = slot
        savedSlot = nil
        context.messages.clear()
        showWholeConsoleProgress(
            label: "Saving…",
            head: "Saving to slot \(slot.value)…",
            detail: "saves the whole console, so this takes a few seconds."
        )
        let began = ContinuousClock.now
        let store = context.dependencies.slots
        let staging = store.stagingURLs(slot, for: game.id)
        let hadState = slots[slot] != nil
        do {
            try await context.session.saveState(to: staging.state)
            _ = context.session.writeSnapshot(to: staging.thumbnail)
            let savedAt = Date.now
            try store.commit(slot, for: game.id, savedAt: savedAt, core: game.system.coreFileName)
            reload()
            savedSlot = slot
            context.messages.show(.ok("State saved", "Slot \(slot.value), \(HubFormat.date(savedAt))."))
            PlayLog.session.info("slot-saved n=\(slot.value) ms=\(HubFormat.milliseconds(since: began))")
        } catch {
            store.discardStaging(slot, for: game.id)
            context.messages.show(Self.saveFailure(error, slot: slot, hadState: hadState))
            let reason = Self.isDiskFull(error) ? "disk-full" : "write-failed"
            PlayLog.session.error("slot-save-failed n=\(slot.value) reason=\(reason)")
        }
        busy = nil
        busyLabel = nil
        close()
    }

    private func load(_ record: SlotRecord) async {
        busy = record.number
        context.messages.clear()
        showWholeConsoleProgress(
            label: "Loading…",
            head: "Loading slot \(record.number.value)…",
            detail: "loads the whole console, so this can take up to 10 seconds."
        )
        let began = ContinuousClock.now
        let store = context.dependencies.slots
        do {
            try await context.session.loadState(from: store.stateURL(record.number, for: game.id))
        } catch {
            context.messages.show(.danger("Couldn’t load the state", "The file is damaged. The game hasn’t changed."))
            PlayLog.session.error("slot-load-failed n=\(record.number.value)")
            busy = nil
            busyLabel = nil
            return
        }
        context.messages.show(.ok(
            "State loaded",
            "From slot \(record.number.value), \(HubFormat.date(record.savedAt))."
        ))
        PlayLog.session.info("slot-loaded n=\(record.number.value) ms=\(HubFormat.milliseconds(since: began))")
        if !record.hasThumbnail {
            attachThumbnail(to: record.number)
        }
        busy = nil
        busyLabel = nil
        close()
    }

    private func showWholeConsoleProgress(label: String, head: String, detail: String) {
        guard showsOwnSavesNote else { return }
        busyLabel = label
        context.messages.show(HubMessage(
            kind: .info,
            head: head,
            detail: "\(game.system.displayName) \(detail)",
            showsSpinner: true
        ))
    }

    private func attachThumbnail(to slot: SlotNumber) {
        let store = context.dependencies.slots
        let staged = store.stagingURLs(slot, for: game.id).thumbnail
        guard context.session.writeSnapshot(to: staged) else { return }
        do {
            try store.attachThumbnail(slot, for: game.id)
            reload()
        } catch {
            store.discardStaging(slot, for: game.id)
            PlayLog.session.error("slot-thumbnail-failed n=\(slot.value)")
        }
    }

    private static func isDiskFull(_ error: any Error) -> Bool {
        switch error {
        case PlayError.saveFailed(.diskFull), StoreWriteError.diskFull: true
        default: false
        }
    }

    private static func saveFailure(_ error: any Error, slot: SlotNumber, hadState: Bool) -> HubMessage {
        let cause = isDiskFull(error) ? "Your Mac is out of disk space." : "The file couldn’t be written."
        let outcome = hadState ? "keeps its earlier state" : "is still empty"
        return .danger("Couldn’t save the state", "\(cause) Slot \(slot.value) \(outcome).")
    }
}
