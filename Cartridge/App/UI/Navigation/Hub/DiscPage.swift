import Foundation
import Observation

@MainActor
@Observable
final class DiscPage: HubPage {
    private(set) var highlighted: Int
    private(set) var busy: Int?

    @ObservationIgnored private let context: HubContext

    init(context: HubContext) {
        self.context = context
        let session = context.session
        highlighted = (0..<session.discCount).first { $0 != session.discIndex } ?? session.discIndex
    }

    var title: String {
        "Change Disc"
    }

    var subtitle: String {
        "\(context.session.game.title). Choose the disc to put in."
    }

    var hints: [Hint] {
        busy == nil
            ? [Hint(kind: .row, label: "Move"), Hint(kind: .confirm, label: "Put In"), Hint(kind: .back, label: "Back")]
            : []
    }

    var counter: String? {
        nil
    }

    var discCount: Int {
        context.session.discCount
    }

    var discInDrive: Int {
        context.session.discIndex
    }

    func handle(_ event: NavigationEvent) {
        guard busy == nil else { return }
        switch event.action {
        case .move(.up):
            move(-1)
        case .move(.down):
            move(1)
        case .confirm:
            Task { await putIn(highlighted) }
        case .back:
            context.exit(.main(highlight: .changeDisc))
        case .move, .pause, .options, .secondary, .section, .text, .erase:
            break
        }
    }

    private func move(_ step: Int) {
        var index = highlighted + step
        while (0..<discCount).contains(index) {
            if index != discInDrive {
                highlighted = index
                return
            }
            index += step
        }
    }

    private func putIn(_ index: Int) async {
        guard index != discInDrive else { return }
        busy = index
        defer { busy = nil }
        do {
            try await context.session.changeDisc(to: index)
            context.messages.show(.ok("Disc \(index + 1) is in"))
            context.exit(.main(highlight: .resume))
        } catch {
            context.messages.show(.danger("Couldn’t change the disc", "The game didn’t accept the disc."))
            context.exit(.main(highlight: .changeDisc))
        }
    }
}
