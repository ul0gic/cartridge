import Foundation
import Observation

enum CheatTarget: Hashable {
    case enterCode
    case myCode(UUID)
    case delete(UUID)
    case entry(CheatKey)
}

@MainActor
@Observable
final class CheatsPage: HubPage {
    var settings: CheatSettings
    var lookup: CheatLookup?
    var target = CheatTarget.enterCode
    var pad: CodePad?
    var isApplying = false

    let arming: Arming<UUID>

    @ObservationIgnored let context: HubContext

    init(context: HubContext) {
        self.context = context
        arming = Arming(messages: context.messages)
        settings = context.cheats.settings
        lookup = context.cheats.cachedLookup
        if let last = context.cheats.lastTarget, focusOrder.contains(last) {
            target = last
        }
        if lookup == nil {
            Task { [weak self] in
                let loaded = await context.cheats.lookup
                self?.lookup = loaded
                if let last = context.cheats.lastTarget, self?.focusOrder.contains(last) == true {
                    self?.target = last
                }
            }
        }
    }

    var system: GameSystem {
        context.session.game.system
    }

    var myCodes: [MyCode] {
        settings.myCodes.sorted { $0.addedAt > $1.addedAt }
    }

    var entries: [CheatEntry] {
        lookup?.entries ?? []
    }

    var hasList: Bool {
        lookup.map { !$0.files.isEmpty } ?? true
    }

    var title: String {
        pad == nil ? "Cheats" : "Enter Code"
    }

    var subtitle: String {
        let game = context.session.game.title
        if pad != nil {
            return "\(game). \(system.displayName) codes."
        }
        let on = context.cheats.enabledCount(in: settings)
        var text = on == 0 ? "\(game). None on." : "\(game). \(on) on"
        if system == .genesis, on > 0 {
            text += ", \(activeCodeCount) codes."
        } else if on > 0 {
            text += "."
        }
        return text
    }

    var hints: [Hint] {
        if pad != nil {
            let confirm = pad?.highlightedKey == .add ? "Add Code" : "Type"
            return [
                Hint(kind: .move, label: "Move"),
                Hint(kind: .confirm, label: confirm),
                Hint(kind: .back, label: "Delete"),
            ]
        }
        return [
            Hint(kind: .row, label: "Move"),
            Hint(kind: .confirm, label: "Select"),
            Hint(kind: .back, label: "Back"),
        ]
    }

    var counter: String? {
        guard case .entry(let key) = target, let index = entries.firstIndex(where: { $0.key == key }) else {
            return nil
        }
        return "\(index + 1) of \(entries.count)"
    }

    var focusOrder: [CheatTarget] {
        [.enterCode] + myCodes.map { .myCode($0.id) } + entries.map { .entry($0.key) }
    }

    var enterCodeDetail: String {
        switch system {
        case .nes: "Game Genie, Pro Action Rocky or address codes"
        case .snes: "Game Genie or Pro Action Replay codes"
        case .genesis: "Game Genie or Action Replay codes"
        case .ps1: "GameShark, Game Buster or Xploder codes"
        case .n64: "GameShark codes"
        case .xbox: "Xbox has no cheat codes"
        }
    }

    var formatGuide: String {
        switch system {
        case .nes: "Game Genie: 6 or 8 letters. Pro Action Rocky: 8 digits. Address: 0300:FF or 0300?05:FF."
        case .snes: "Game Genie: 1234-ABCD. Pro Action Replay: 8 digits."
        case .genesis: "Game Genie: ABCD-EFGH. Action Replay: FF0410:0009."
        case .ps1: "GameShark, Game Buster or Xploder: 8 digits, a space, 4 digits. Join codes with +."
        case .n64: "GameShark: 8 digits, a space, 4 digits. Join codes with +."
        case .xbox: "Xbox has no cheat codes."
        }
    }

    func isOn(_ entry: CheatEntry) -> Bool {
        settings.enabled.contains(entry.key.rawValue)
    }

    func handle(_ event: NavigationEvent) {
        guard !isApplying else { return }
        if pad != nil {
            handlePad(event)
        } else {
            handleList(event)
        }
    }

    private func handleList(_ event: NavigationEvent) {
        switch event.action {
        case .move(let direction):
            move(direction)
        case .confirm:
            confirm()
        case .back:
            context.cheats.lastTarget = target
            context.exit(.main(highlight: .cheats))
        case .pause, .options, .secondary, .section, .text, .erase:
            break
        }
    }

    private func move(_ direction: Direction) {
        switch (direction, target) {
        case (.right, .myCode(let id)):
            retarget(.delete(id))
        case (.left, .delete(let id)):
            retarget(.myCode(id))
        case (.up, _), (.down, _):
            let order = focusOrder
            let current = if case .delete(let id) = target {
                CheatTarget.myCode(id)
            } else {
                target
            }
            guard let index = order.firstIndex(of: current) else { return }
            let next = index + (direction == .up ? -1 : 1)
            if order.indices.contains(next) {
                retarget(order[next])
            }
        default:
            break
        }
    }

    private func retarget(_ next: CheatTarget) {
        arming.disarm()
        target = next
    }

    private func confirm() {
        switch target {
        case .enterCode:
            context.messages.clear()
            pad = CodePad(system: system)
        case .myCode(let id):
            if let code = settings.myCodes.first(where: { $0.id == id }) {
                Task { await toggle(myCode: code) }
            }
        case .delete(let id):
            confirmDelete(id)
        case .entry(let key):
            if let entry = entries.first(where: { $0.key == key }) {
                Task { await toggle(entry: entry) }
            }
        }
    }

    private func confirmDelete(_ id: UUID) {
        guard let code = settings.myCodes.first(where: { $0.id == id }) else { return }
        if arming.isArmed(id) {
            arming.disarm()
            Task { await delete(code) }
        } else {
            arming.arm(
                id,
                message: .warn(
                    "Delete this code?",
                    "Press \(context.confirmName()) again to delete \(code.code) from My codes."
                )
            )
        }
    }

    private func handlePad(_ event: NavigationEvent) {
        guard var current = pad else { return }
        switch event.action {
        case .move(let direction):
            current.move(direction)
        case .confirm:
            context.messages.clear()
            if current.highlightedKey == .add {
                addCode(current.code)
            } else {
                current.press(current.highlightedKey)
            }
        case .back:
            context.messages.clear()
            if current.code.isEmpty {
                pad = nil
                target = .enterCode
                return
            }
            current.eraseLast()
        case .text(let text):
            context.messages.clear()
            current.type(text)
        case .erase:
            context.messages.clear()
            current.eraseLast()
        case .pause, .options, .secondary, .section:
            break
        }
        pad = current
    }
}
