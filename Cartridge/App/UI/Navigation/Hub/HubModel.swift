import Foundation
import Observation

enum HubCardState {
    case resting
    case disabled
    case busy
    case armed
}

enum HubCardStatus: Equatable {
    case text(String)
    case armed(verb: String)
}

struct HubCard: Identifiable {
    let id: HubCardID
    let glyph: String
    let label: String
    let status: HubCardStatus
    var state = HubCardState.resting

    var isEnabled: Bool {
        state != .disabled
    }
}

enum RewindStatus {
    case rewinding
    case oldest
}

struct HubHooks {
    let stopRecording: () async -> Void
    let restart: (RestartReason) -> Void
    let chooseSaveFile: (_ message: String) async -> URL?
}

@MainActor
@Observable
final class HubModel {
    private static let rewindPoll = Duration.milliseconds(50)

    private(set) var page: HubPageModel?
    private(set) var highlighted = HubCardID.resume
    private(set) var busy: HubCardID?
    private(set) var isControllerConnected: Bool
    private(set) var isRestarting = false
    private(set) var rewind: RewindStatus?
    private(set) var slotsUsed = 0
    private(set) var cheatsOn = 0
    private(set) var batterySize: Int?

    let session: any PlaySessionControlling
    let messages = HubMessageBox()
    let arming: Arming<HubCardID>

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private let cheats: SessionCheats
    @ObservationIgnored private let hooks: HubHooks
    @ObservationIgnored private var isRewindHeld = false
    @ObservationIgnored private var speedBeforeHold = PlaySpeed.normal
    @ObservationIgnored private var rewindTask: Task<Void, Never>?
    @ObservationIgnored private var lastColumn = 0

    init(
        session: any PlaySessionControlling,
        dependencies: AppDependencies,
        cheats: SessionCheats,
        isControllerConnected: Bool,
        hooks: HubHooks
    ) {
        self.session = session
        self.dependencies = dependencies
        self.cheats = cheats
        self.isControllerConnected = isControllerConnected
        self.hooks = hooks
        arming = Arming(messages: messages)
        if !isControllerConnected {
            highlighted = .saveStates
        }
        refreshSummary()
        Task { await loadDeferredSummary() }
    }

    var canRewind: Bool {
        session.game.system.playFeatures.contains(.rewind)
    }

    var hasFastForward: Bool {
        session.game.system.triggerRole == .gameButtons
    }

    var isFastForwardOn: Bool {
        session.requestedSpeed == .fastForward
    }

    var rows: [[HubCardID]] {
        var rows: [[HubCardID]] = [hasFastForward ? [.resume, .fastForward] : [.resume]]
        rows.append([.saveStates, .cheats])
        rows.append([.saveFile, .display])
        if case .multiDisc = session.game.kind {
            rows.append([.changeDisc])
        }
        rows.append([.reset, .quit])
        return rows
    }

    func setControllerConnected(_ connected: Bool) {
        guard connected != isControllerConnected else { return }
        isControllerConnected = connected
        if connected {
            highlight(.resume)
        } else if highlighted == .resume {
            highlight(.saveStates)
        }
    }

    func handle(_ event: NavigationEvent) {
        guard busy == nil, !isRestarting else { return }
        if event.action == .pause {
            resumeIfPossible()
        } else if let page {
            page.base.handle(event)
        } else {
            handleMain(event)
        }
    }

    func rewindHeld(_ held: Bool) {
        guard canRewind, busy == nil, !isRestarting, held != isRewindHeld else { return }
        isRewindHeld = held
        if held {
            speedBeforeHold = session.requestedSpeed
            session.setSpeed(.rewind)
            rewind = .rewinding
            rewindTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    rewind = session.activeSpeed == .rewindHolding ? .oldest : .rewinding
                    try? await Task.sleep(for: Self.rewindPoll)
                }
            }
        } else {
            rewindTask?.cancel()
            rewindTask = nil
            rewind = nil
            session.setSpeed(speedBeforeHold)
        }
    }

    private func beginRestart(_ reason: RestartReason) {
        isRestarting = true
        hooks.restart(reason)
    }

    private func handleMain(_ event: NavigationEvent) {
        switch event.action {
        case .move(let direction):
            move(direction)
        case .confirm:
            activate(highlighted)
        case .back:
            resumeIfPossible()
        case .pause, .options, .secondary, .section, .text, .erase:
            break
        }
    }

    private func resumeIfPossible() {
        guard isControllerConnected else { return }
        resume(speed: nil)
    }

    private func resume(speed: PlaySpeed?) {
        session.setSpeed(speed ?? (isRewindHeld ? .normal : session.requestedSpeed))
        session.resume()
    }

    private func activate(_ card: HubCardID) {
        guard cards.first(where: { $0.id == card })?.isEnabled == true else { return }
        switch card {
        case .resume:
            resume(speed: nil)
        case .fastForward:
            resume(speed: isFastForwardOn ? .normal : .fastForward)
        case .saveStates, .cheats, .saveFile, .display, .changeDisc:
            open(card)
        case .reset:
            confirmReset()
        case .quit:
            Task { await quit() }
        }
    }

    private func confirmReset() {
        if arming.isArmed(.reset) {
            arming.disarm()
            session.setSpeed(isRewindHeld ? .normal : session.requestedSpeed)
            Task { await session.reset() }
        } else {
            arming.arm(
                .reset,
                message: .warn("Reset \(session.game.title)?", "Play since your last save state will be lost.")
            )
        }
    }

    private func quit() async {
        if arming.isArmed(.quit) {
            arming.disarm()
            busy = .quit
            await hooks.stopRecording()
            await session.quitWithoutSaving()
            return
        }
        busy = .quit
        messages.clear()
        defer { busy = nil }
        await hooks.stopRecording()
        do {
            _ = try await session.quitToLibrary()
        } catch PlayError.quitSaveFailed(let failure) {
            messages.show(Self.quitFailureMessage(failure))
            arming.arm(.quit)
        } catch {
            return
        }
    }

    private func open(_ card: HubCardID) {
        if card == .saveFile, batterySize == nil {
            Task {
                batterySize = await session.batterySaveSize()
                open(card)
            }
            return
        }
        arming.disarm()
        messages.clear()
        let context = HubContext(
            session: session,
            dependencies: dependencies,
            cheats: cheats,
            messages: messages,
            exit: { [weak self] in self?.exit($0) },
            confirmName: { [weak self] in self?.isControllerConnected == false ? "Return" : "⊗" },
            chooseSaveFile: hooks.chooseSaveFile
        )
        switch card {
        case .saveStates: page = .states(SaveStatesPage(context: context))
        case .cheats: page = .cheats(CheatsPage(context: context))
        case .saveFile: page = .file(SaveFilePage(context: context, batterySize: batterySize ?? 0))
        case .display: page = .display(DisplayPage(context: context))
        case .changeDisc: page = .disc(DiscPage(context: context))
        case .resume, .fastForward, .reset, .quit: break
        }
    }

    private func exit(_ exit: HubPageExit) {
        switch exit {
        case .main(let card):
            page = nil
            highlight(card)
            refreshSummary()
        case .restart(let reason):
            beginRestart(reason)
        }
    }

    private func move(_ direction: Direction) {
        let rows = rows
        guard let row = rows.firstIndex(where: { $0.contains(highlighted) }),
              let column = rows[row].firstIndex(of: highlighted)
        else { return }
        switch direction {
        case .left, .right:
            let target = column + (direction == .left ? -1 : 1)
            guard rows[row].indices.contains(target), isEnabled(rows[row][target]) else { return }
            highlight(rows[row][target])
        case .up, .down:
            let step = direction == .up ? -1 : 1
            var index = row + step
            while rows.indices.contains(index) {
                if let card = landing(in: rows[index]) {
                    highlight(card, updatesColumn: false)
                    return
                }
                index += step
            }
        }
    }

    private func landing(in row: [HubCardID]) -> HubCardID? {
        let preferred = row.count == 1 ? 0 : min(lastColumn, row.count - 1)
        return ([preferred] + row.indices.filter { $0 != preferred }).map { row[$0] }.first(where: isEnabled)
    }

    private func isEnabled(_ card: HubCardID) -> Bool {
        cards.first { $0.id == card }?.isEnabled == true
    }

    private func highlight(_ card: HubCardID, updatesColumn: Bool = true) {
        if highlighted != card {
            arming.disarm()
        }
        highlighted = card
        guard updatesColumn, let row = rows.first(where: { $0.contains(card) }), row.count == 2 else { return }
        lastColumn = row.firstIndex(of: card) ?? lastColumn
    }

    private func refreshSummary() {
        let game = session.game
        let legacy = dependencies.library.playRecord(for: game.id)?.manualStateAt
        slotsUsed = dependencies.slots.slots(for: game.id, legacyManualStateAt: legacy).count
        cheatsOn = cheats.enabledCount(in: cheats.settings)
    }

    private func loadDeferredSummary() async {
        _ = await cheats.lookup
        cheatsOn = cheats.enabledCount(in: cheats.settings)
        batterySize = await session.batterySaveSize()
    }

    private static func quitFailureMessage(_ failure: SaveFailure) -> HubMessage {
        let detail = failure == .diskFull
            ? "Your Mac is out of disk space. Free some space, then choose Quit to Library again."
            : "The file couldn’t be written. Choose Quit to Library again."
        return .danger("Couldn’t save your place", detail)
    }
}
