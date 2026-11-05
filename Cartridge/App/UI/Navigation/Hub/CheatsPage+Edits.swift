import Foundation

private enum CheatOutcome {
    case applied
    case rejected
    case failed(HubMessage)
}

extension CheatsPage {
    func addCode(_ typed: String) {
        switch CheatCodeFormat.normalize(typed, for: system) {
        case .failure(.empty):
            break
        case .failure(.tooLong), .failure(.noFormat):
            context.messages.show(.danger("That isn’t \(article) \(system.displayName) code", refusalDetail))
        case .success(let normalized):
            let mine = MyCode(id: UUID(), code: normalized, addedAt: .now, isEnabled: true)
            var next = settings
            next.myCodes.append(mine)
            if exceedsGenesisLimit(next) {
                context.messages.show(Self.limitMessage)
                return
            }
            Task { await add(mine, to: next) }
        }
    }

    private func add(_ mine: MyCode, to next: CheatSettings) async {
        switch await commit(next) {
        case .applied:
            context.messages.show(.ok("Code added", "It’s on. You’ll see it when you resume."))
        case .rejected:
            var off = next
            off.myCodes[off.myCodes.count - 1].isEnabled = false
            guard case .applied = await commit(off) else { return }
            context.messages.show(Self.refusedMessage(mine.code))
        case .failed(let message):
            context.messages.show(message)
            return
        }
        pad = nil
        target = .myCode(mine.id)
    }

    func toggle(entry: CheatEntry) async {
        var next = settings
        let key = entry.key.rawValue
        let turningOn = !next.enabled.contains(key)
        if turningOn {
            next.enabled.append(key)
        } else {
            next.enabled.removeAll { $0 == key }
        }
        await change(to: next, turningOn: turningOn, name: entry.description)
    }

    func toggle(myCode code: MyCode) async {
        var next = settings
        guard let index = next.myCodes.firstIndex(where: { $0.id == code.id }) else { return }
        next.myCodes[index].isEnabled.toggle()
        await change(to: next, turningOn: next.myCodes[index].isEnabled, name: code.code)
    }

    private func change(to next: CheatSettings, turningOn: Bool, name: String) async {
        context.messages.clear()
        if turningOn, exceedsGenesisLimit(next) {
            context.messages.show(Self.limitMessage)
            return
        }
        switch await commit(next) {
        case .applied: break
        case .rejected: context.messages.show(Self.refusedMessage(name))
        case .failed(let message): context.messages.show(message)
        }
    }

    func delete(_ code: MyCode) async {
        let order = focusOrder
        var next = settings
        next.myCodes.removeAll { $0.id == code.id }
        guard case .applied = await commit(next) else { return }
        let index = order.firstIndex(of: .myCode(code.id)) ?? 0
        let remaining = focusOrder
        target = remaining.indices.contains(index) ? remaining[index] : remaining[max(index - 1, 0)]
    }

    private func commit(_ next: CheatSettings) async -> CheatOutcome {
        let previous = settings
        do {
            try context.cheats.save(next)
        } catch {
            let cause = error == .diskFull ? "Your Mac is out of disk space." : "The file couldn’t be written."
            return .failed(.danger("Couldn’t save your cheats", "\(cause) Nothing changed."))
        }
        settings = next
        isApplying = true
        defer { isApplying = false }
        do {
            try await context.cheats.apply(next, to: context.session)
            return .applied
        } catch {
            settings = previous
            do {
                try context.cheats.save(previous)
            } catch {
                PlayLog.session.error("cheat-settings-revert-failed")
            }
            guard case PlayError.cheatsRejected = error else {
                return .failed(.danger(
                    "Couldn’t update the cheats",
                    "The game didn’t answer. Your cheats are as they were."
                ))
            }
            return .rejected
        }
    }

    var activeCodeCount: Int {
        let codes = context.cheats.codes(for: settings, in: lookup ?? Self.noList)
        return context.cheats.codeCount(of: codes)
    }

    private func exceedsGenesisLimit(_ next: CheatSettings) -> Bool {
        guard system == .genesis else { return false }
        let codes = context.cheats.codes(for: next, in: lookup ?? Self.noList)
        return context.cheats.codeCount(of: codes) > CheatCodeFormat.genesisCodeLimit
    }

    var article: String {
        switch system {
        case .nes, .snes, .n64, .xbox: "an"
        case .genesis, .ps1: "a"
        }
    }

    var refusalDetail: String {
        switch system {
        case .nes: "NES takes Game Genie (6 or 8 letters), Pro Action Rocky (8 digits) or an address like 0300:FF."
        case .snes: "SNES takes Game Genie (1234-ABCD) or Pro Action Replay (8 digits) codes."
        case .genesis: "Genesis takes Game Genie (ABCD-EFGH) or Action Replay (FF0410:0009) codes."
        case .ps1: "PS1 takes 8 digits, a space and 4 digits, joined with +."
        case .n64: "N64 takes 8 digits, a space and 4 digits, joined with +."
        case .xbox: "Xbox takes no cheat codes."
        }
    }

    private static let noList = CheatLookup(files: [], entries: [])

    private static let limitMessage = HubMessage.warn(
        "Too many codes on",
        "Genesis games take up to \(CheatCodeFormat.genesisCodeLimit) codes at once. Turn one off first."
    )

    private static func refusedMessage(_ name: String) -> HubMessage {
        .danger("Couldn’t turn on \(name)", "The game refused this code. Your other cheats stay on.")
    }
}
