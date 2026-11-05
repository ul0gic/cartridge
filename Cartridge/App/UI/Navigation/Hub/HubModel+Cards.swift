import Foundation

extension HubModel {
    var title: String {
        page?.base.title ?? session.game.title
    }

    var subtitle: String {
        if let page {
            return page.base.subtitle
        }
        let system = session.game.system.displayName
        var text = session.discCount > 1
            ? "Paused. \(system), disc \(session.discIndex + 1) of \(session.discCount)."
            : "Paused. \(system)."
        if hasFastForward, isFastForwardOn {
            text += " Fast forward is on."
        }
        return text
    }

    var hints: [Hint] {
        if busy == .quit || isRestarting {
            return []
        }
        if let page {
            return page.base.hints
        }
        let base = [Hint(kind: .move, label: "Move"), Hint(kind: .confirm, label: "Select")]
        return isControllerConnected ? base + [Hint(kind: .back, label: "Resume")] : base
    }

    var showsRewindHint: Bool {
        isControllerConnected && canRewind && page == nil && busy == nil
    }

    var counter: String? {
        page?.base.counter
    }

    var messageStack: [HubMessage] {
        var stack: [HubMessage] = []
        if let rewind {
            stack.append(Self.rewindMessage(rewind))
        }
        if let current = messages.current {
            stack.append(current)
        }
        if !isControllerConnected {
            stack.append(.disconnected)
        }
        return stack
    }

    var cards: [HubCard] {
        let byID: [HubCardID: HubCard] = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })
        return rows.flatMap(\.self).compactMap { byID[$0] }.map { card in
            var card = card
            if busy == card.id {
                card.state = .busy
            } else if busy == .quit {
                card.state = .disabled
            }
            return card
        }
    }

    private var allCards: [HubCard] {
        [resumeCard, fastForwardCard, saveStatesCard, cheatsCard, saveFileCard, displayCard, changeDiscCard]
            + [resetCard, quitCard]
    }

    private var resumeCard: HubCard {
        HubCard(
            id: .resume,
            glyph: "play.fill",
            label: "Resume",
            status: .text(isControllerConnected ? "Back to the game" : "Connect a controller to play"),
            state: isControllerConnected ? .resting : .disabled
        )
    }

    private func isUnavailable(_ feature: PlayFeatures) -> Bool {
        !session.game.system.playFeatures.contains(feature)
    }

    private var unavailableStatus: HubCardStatus {
        .text("Not available on \(session.game.system.displayName)")
    }

    private var fastForwardCard: HubCard {
        let on = isFastForwardOn
        let unavailable = isUnavailable(.fastForward)
        return HubCard(
            id: .fastForward,
            glyph: on ? "tortoise.fill" : "forward.fill",
            label: on ? "Normal Speed" : "Fast Forward",
            status: unavailable ? unavailableStatus : .text(on ? "Fast forward is on" : "Play up to 4× faster"),
            state: unavailable ? .disabled : .resting
        )
    }

    private var saveStatesCard: HubCard {
        let status = slotsUsed == 0 ? "No save states yet" : "\(slotsUsed) of \(SlotNumber.all.count) slots used"
        return HubCard(id: .saveStates, glyph: "rectangle.stack", label: "Save States", status: .text(status))
    }

    private var cheatsCard: HubCard {
        let unavailable = isUnavailable(.cheats)
        return HubCard(
            id: .cheats,
            glyph: "wand.and.stars",
            label: "Cheats",
            status: unavailable ? unavailableStatus : .text(cheatsOn == 0 ? "None on" : "\(cheatsOn) on"),
            state: unavailable ? .disabled : .resting
        )
    }

    private var saveFileCard: HubCard {
        let unavailable = isUnavailable(.saveFile)
        let status = batterySize == 0 ? "This game keeps no save file" : "Back up, restore or import"
        return HubCard(
            id: .saveFile,
            glyph: "memorychip",
            label: "Save File",
            status: unavailable ? unavailableStatus : .text(status),
            state: unavailable ? .disabled : .resting
        )
    }

    private var displayCard: HubCard {
        HubCard(id: .display, glyph: "tv", label: "Display", status: .text(session.look.displayName))
    }

    private var changeDiscCard: HubCard {
        HubCard(
            id: .changeDisc,
            glyph: "opticaldisc",
            label: "Change Disc",
            status: .text("Disc \(session.discIndex + 1) of \(session.discCount) is in")
        )
    }

    private var resetCard: HubCard {
        HubCard(
            id: .reset,
            glyph: "arrow.counterclockwise",
            label: "Reset",
            status: arming.isArmed(.reset) ? .armed(verb: "reset") : .text("Start the game over"),
            state: arming.isArmed(.reset) ? .armed : .resting
        )
    }

    private var quitCard: HubCard {
        let status: HubCardStatus = switch (busy == .quit, arming.isArmed(.quit)) {
        case (true, _): .text("Saving your place…")
        case (_, true): .armed(verb: "quit without saving")
        default: .text("Saves your place")
        }
        return HubCard(
            id: .quit,
            glyph: "square.grid.2x2",
            label: "Quit to Library",
            status: status,
            state: arming.isArmed(.quit) ? .armed : .resting
        )
    }

    private static func rewindMessage(_ rewind: RewindStatus) -> HubMessage {
        switch rewind {
        case .rewinding:
            HubMessage(kind: .info, head: "Rewinding", detail: "Release L2 to stop", glyph: "backward.fill")
        case .oldest:
            HubMessage(
                kind: .info,
                head: "Can’t rewind further",
                detail: "This is the oldest moment kept",
                glyph: "backward.end.fill"
            )
        }
    }
}
