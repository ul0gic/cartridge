import CoreGraphics
import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class DisplayPage: HubPage {
    private(set) var highlighted: DisplayLook

    let preview: CGImage?

    @ObservationIgnored private let context: HubContext

    init(context: HubContext) {
        self.context = context
        highlighted = context.session.look
        preview = Self.previewImage(of: context.session)
    }

    var title: String {
        "Display"
    }

    var subtitle: String {
        "For every \(context.session.game.system.displayName) game. The picture changes as you choose."
    }

    var hints: [Hint] {
        [
            Hint(kind: .row, label: "Move"),
            Hint(kind: .confirm, label: "Choose"),
            Hint(kind: .back, label: "Back"),
        ]
    }

    var counter: String? {
        nil
    }

    var inUse: DisplayLook {
        context.session.look
    }

    func handle(_ event: NavigationEvent) {
        switch event.action {
        case .move(.up):
            step(-1)
        case .move(.down):
            step(1)
        case .confirm:
            choose(highlighted)
        case .back:
            context.exit(.main(highlight: .display))
        case .move, .pause, .options, .secondary, .section, .text, .erase:
            break
        }
    }

    private func step(_ offset: Int) {
        let looks = DisplayLook.allCases
        guard let index = looks.firstIndex(of: highlighted), looks.indices.contains(index + offset) else { return }
        highlighted = looks[index + offset]
    }

    private func choose(_ look: DisplayLook) {
        let system = context.session.game.system
        context.session.look = look
        context.dependencies.looks.setLook(look, for: system)
        PlayLog.session.info("look system=\(system.rawValue) look=\(look.rawValue)")
    }

    private static func previewImage(of session: any PlaySessionControlling) -> CGImage? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cartridge-look-preview-\(UUID().uuidString).png", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: url) }
        guard session.writeSnapshot(to: url), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
