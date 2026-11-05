import Foundation
import Observation

enum SaveFileTarget: Hashable {
    case backUp
    case restore
    case importSave
    case backup(URL)
}

@MainActor
@Observable
final class SaveFilePage: HubPage {
    private(set) var target = SaveFileTarget.backUp
    private(set) var isListing = false
    private(set) var backups: [SaveBackup]
    private(set) var busy: SaveFileTarget?

    let batterySize: Int
    let writtenAt: Date?
    let arming: Arming<SaveFileTarget>

    @ObservationIgnored private let context: HubContext
    @ObservationIgnored private var pendingImport: URL?

    init(context: HubContext, batterySize: Int) {
        let id = context.session.game.id
        self.context = context
        self.batterySize = batterySize
        arming = Arming(messages: context.messages)
        backups = context.dependencies.backups.backups(for: id)
        writtenAt = try? FileManager.default.attributesOfItem(atPath: StoragePaths.batterySave(for: id).path)[
            .modificationDate
        ] as? Date
    }

    var hasSave: Bool {
        batterySize > 0
    }

    var unit: String {
        context.session.game.system == .ps1 ? "card" : "save"
    }

    var title: String {
        isListing ? "Restore" : "Save File"
    }

    var subtitle: String {
        let game = context.session.game
        if isListing {
            return "\(game.title). Newest first."
        }
        let noun = game.system == .ps1 ? "Memory card 1" : "Battery save"
        return writtenAt.map { "\(noun). Written \(HubFormat.date($0))." } ?? "\(noun)."
    }

    var hints: [Hint] {
        if busy != nil {
            return []
        }
        if !hasSave {
            return [Hint(kind: .back, label: "Back")]
        }
        return [
            Hint(kind: .row, label: "Move"),
            Hint(kind: .confirm, label: isListing ? "Restore" : "Select"),
            Hint(kind: .back, label: "Back"),
        ]
    }

    var counter: String? {
        nil
    }

    var isJustBackedUp: Bool {
        context.messages.current?.head == "Backed up"
    }

    func handle(_ event: NavigationEvent) {
        guard busy == nil else { return }
        switch event.action {
        case .move(.up):
            step(-1)
        case .move(.down):
            step(1)
        case .confirm:
            confirm()
        case .back:
            goBack()
        case .move, .pause, .options, .secondary, .section, .text, .erase:
            break
        }
    }

    private var order: [SaveFileTarget] {
        if isListing {
            return backups.map { .backup($0.url) }
        }
        return hasSave ? [.backUp] + (backups.isEmpty ? [] : [.restore]) + [.importSave] : []
    }

    private func step(_ offset: Int) {
        let order = order
        guard let index = order.firstIndex(of: target), order.indices.contains(index + offset) else { return }
        arming.disarm()
        target = order[index + offset]
    }

    private func goBack() {
        arming.disarm()
        if isListing {
            isListing = false
            target = .restore
        } else {
            context.exit(.main(highlight: .saveFile))
        }
    }

    private func confirm() {
        switch target {
        case .backUp:
            Task { await backUp() }
        case .restore:
            isListing = true
            target = backups.first.map { .backup($0.url) } ?? .backUp
            context.messages.clear()
        case .importSave:
            if arming.isArmed(.importSave), let url = pendingImport {
                arming.disarm()
                Task { await commitImport(url) }
            } else {
                Task { await chooseImport() }
            }
        case .backup(let url):
            guard let backup = backups.first(where: { $0.url == url }) else { return }
            if arming.isArmed(target) {
                arming.disarm()
                Task { await restore(backup) }
            } else {
                arming.arm(
                    target,
                    message: .warn(
                        "Restore the \(unit) from \(HubFormat.date(backup.createdAt))?",
                        "\(Self.restartWarning) This \(unit) is kept as a backup."
                    )
                )
            }
        }
    }

    private func backUp() async {
        busy = .backUp
        context.messages.clear()
        defer { busy = nil }
        do {
            _ = try await context.session.flushBatterySave()
            let backup = try context.dependencies.backups.backUp(context.session.game.id)
            backups = context.dependencies.backups.backups(for: context.session.game.id)
            context.messages.show(.ok("Backed up", "The copy from \(HubFormat.date(backup.createdAt)) is in Restore."))
        } catch {
            context.messages.show(.danger("Couldn’t back up the \(unit)", Self.failureDetail(error)))
        }
    }

    private func restore(_ backup: SaveBackup) async {
        busy = .backup(backup.url)
        defer { busy = nil }
        do {
            _ = try await context.session.flushBatterySave()
            _ = try context.dependencies.backups.restore(backup, for: context.session.game.id)
        } catch {
            context.messages.show(.danger("Couldn’t restore the \(unit)", Self.failureDetail(error)))
            return
        }
        context.exit(.restart(.restore))
    }

    private func chooseImport() async {
        busy = .importSave
        context.messages.show(.info(
            "Choose a file in the Finder window",
            "The controller does nothing until the window closes.",
            glyph: "folder"
        ))
        let title = context.session.game.title
        let url = await context.chooseSaveFile("Choose a save file for \(title).")
        busy = nil
        context.messages.clear()
        guard let url else { return }
        let name = url.lastPathComponent
        let size: Int
        do {
            let values = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw SaveFileError.notARegularFile
            }
            size = fileSize
        } catch {
            context.messages.show(.danger("Couldn’t read that file", "\(name) couldn’t be opened. Nothing changed."))
            return
        }
        guard size == batterySize else {
            context.messages.show(Self.wrongSizeMessage(name: name, actual: size, expected: batterySize, unit: unit))
            return
        }
        pendingImport = url
        arming.arm(
            .importSave,
            message: .warn("Import \(name)?", "\(Self.restartWarning) This \(unit) is kept as a backup.")
        )
    }

    private func commitImport(_ url: URL) async {
        busy = .importSave
        defer { busy = nil }
        do {
            _ = try await context.session.flushBatterySave()
            _ = try context.dependencies.backups.importSave(
                from: url,
                for: context.session.game.id,
                expectedBytes: batterySize
            )
        } catch {
            context.messages.show(Self.importFailure(error, name: url.lastPathComponent, unit: unit))
            return
        }
        context.exit(.restart(.importSave))
    }

    private static let restartWarning = "The game restarts from power-on. Play since its last save is lost."

    private static func failureDetail(_ error: any Error) -> String {
        let diskFull = switch error {
        case SaveFileError.diskFull, PlayError.saveFailed(.diskFull): true
        default: false
        }
        let cause = diskFull ? "Your Mac is out of disk space." : "The file couldn’t be written."
        return "\(cause) Nothing changed."
    }

    private static func wrongSizeMessage(name: String, actual: Int, expected: Int, unit: String) -> HubMessage {
        .danger(
            "That file is the wrong size",
            "\(name) is \(HubFormat.byteCount(actual)) bytes; this game’s \(unit) is \(HubFormat.byteCount(expected)) "
                + "bytes. Nothing changed."
        )
    }

    private static func importFailure(_ error: any Error, name: String, unit: String) -> HubMessage {
        guard let failure = error as? SaveFileError else {
            return .danger("Couldn’t import the \(unit)", failureDetail(error))
        }
        switch failure {
        case .wrongSize:
            return .danger("That file is the wrong size", "\(name) doesn’t match this game’s \(unit). Nothing changed.")
        case .notARegularFile, .unreadable:
            return .danger("Couldn’t read that file", "\(name) couldn’t be opened. Nothing changed.")
        case .noBatterySave, .writeFailed, .diskFull:
            return .danger("Couldn’t import the \(unit)", failureDetail(error))
        }
    }
}
