import AppKit
import SwiftUI

extension AppModel {
    func handle(_ event: NavigationEvent) {
        guard !isPickerOpen else { return }
        animatesScroll = !event.isRepeat && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        respond(to: event)
        if consumeCrashBand(event) {
            return
        }
        switch route {
        case .welcome:
            if event.action == .confirm {
                chooseROMFolder()
            }
        case .denied:
            confirmButton(event, count: 3).map(activateDeniedButton)
        case .scanning:
            browse(event)
        case .library:
            handleHome(event)
        case .gamePanel, .settings, .about, .controller, .play:
            handleSecondary(event)
        case .launch:
            handleIntro(event)
        }
    }

    private func respond(to event: NavigationEvent) {
        guard route != .launch, !route.isPlay else { return }
        let sound: UISound? = switch event.action {
        case .move: .move
        case .confirm: .select
        case .back: .back
        case .section: .tab
        case .options, .secondary, .pause, .text, .erase: nil
        }
        if let sound {
            UISound.play(sound)
        }
        guard event.source == .controller, sound != nil else { return }
        dependencies.controller.feedback(event.action == .confirm ? .confirm : .tick)
    }

    private func handleIntro(_ event: NavigationEvent) {
        switch event.action {
        case .confirm, .back, .move, .pause, .options: skipIntro()
        case .secondary, .section, .text, .erase: break
        }
    }

    private func handleSecondary(_ event: NavigationEvent) {
        switch route {
        case .gamePanel(let id): handlePanel(event, id: id)
        case .settings: handleSettings(event)
        case .about: handleAbout(event)
        case .controller(let tab): handleControllerGuide(event, tab: tab)
        case .play: handlePlayEvent(event)
        case .launch, .welcome, .denied, .scanning, .library: break
        }
    }

    func showAbout() {
        guard isMenuEnabled else { return }
        resetSlotPicker()
        show(.about)
    }

    func showSettings() {
        guard canOpenSettings else { return }
        show(.settings)
    }

    func chooseROMFolder() {
        guard isMenuEnabled, !isPickerOpen else { return }
        Task { await pickROMFolder() }
    }

    func rescanLibrary() {
        guard canRescan else { return }
        Task { await dependencies.library.rescan() }
    }

    func chooseBIOSFolder() {
        guard isMenuEnabled, !isPickerOpen else { return }
        if route != .settings, !isPanelRoute {
            show(.settings)
        }
        Task {
            isPickerOpen = true
            let url = await FolderPicker.choose(message: "Choose the folder that holds your PS1 BIOS files.")
            isPickerOpen = false
            guard let url else { return }
            biosResult = await dependencies.bios.importBIOS(from: url)
        }
    }

    func chooseXboxFirmwareFolder() {
        guard isMenuEnabled, !isPickerOpen else { return }
        if route != .settings, !isPanelRoute {
            show(.settings)
        }
        Task {
            isPickerOpen = true
            let url = await FolderPicker.choose(
                message: "Choose the folder with your Xbox boot ROM and Complex 4627 BIOS."
            )
            isPickerOpen = false
            guard let url else { return }
            xboxFirmwareImport = await dependencies.xboxFirmware.importFirmware(from: url)
        }
    }

    private var isPanelRoute: Bool {
        if case .gamePanel = route {
            return true
        }
        return false
    }

    var returnRoute: Route {
        isForegroundScan ? .scanning : .library
    }

    private func consumeCrashBand(_ event: NavigationEvent) -> Bool {
        guard crashedGameTitle != nil, route == .library else { return false }
        switch event.action {
        case .confirm, .back:
            dismissCrashBand()
            return true
        case .move, .options, .secondary, .pause, .section, .text, .erase:
            return false
        }
    }

    private func handleHome(_ event: NavigationEvent) {
        switch homeState {
        case .browse:
            handleShell(event)
        case .empty:
            if event.action == .options {
                showSettings()
            } else if confirmButton(event, count: 1) != nil {
                chooseROMFolder()
            }
        case .missing:
            if event.action == .options {
                showSettings()
            } else if let button = confirmButton(event, count: 2) {
                if button == 0 {
                    Task { await retry() }
                } else {
                    chooseROMFolder()
                }
            }
        }
    }

    private func browse(_ event: NavigationEvent) {
        let rows = rows
        switch event.action {
        case .move(let direction):
            if cursor.move(direction, in: rows), let slot = cursor.slot(in: rows) {
                dependencies.library.saveSelection(
                    LibrarySelection(rowKey: rows[slot.rowIndex].key.rawKey, gameID: slot.game.id)
                )
            }
        case .confirm:
            if let slot = cursor.slot(in: rows) {
                show(.gamePanel(slot.game.id))
            }
        case .options:
            showSettings()
        case .back, .pause, .secondary, .section, .text, .erase:
            break
        }
    }

    func confirmButton(_ event: NavigationEvent, count: Int) -> Int? {
        switch event.action {
        case .move(.left):
            focusedButton = max(0, focusedButton - 1)
        case .move(.right):
            focusedButton = min(count - 1, focusedButton + 1)
        case .confirm:
            return focusedButton
        case .move, .back, .options, .secondary, .pause, .section, .text, .erase:
            break
        }
        return nil
    }

    private func activateDeniedButton(_ index: Int) {
        switch index {
        case 0:
            if let url = Self.filesAndFoldersURL {
                NSWorkspace.shared.open(url)
            }
        case 1:
            chooseROMFolder()
        default:
            Task { await retry() }
        }
    }

    private func retry() async {
        await dependencies.library.retry()
        settle()
    }

    private func pickROMFolder() async {
        isPickerOpen = true
        let url = await FolderPicker.choose(message: "Choose the folder that holds your games.")
        isPickerOpen = false
        guard let url else { return }
        resetSlotPicker()
        cursor = LibraryCursor()
        isForegroundScan = true
        show(.scanning)
        await dependencies.library.chooseFolder(url)
        isForegroundScan = false
        guard route == .scanning else { return }
        settle()
        let count = dependencies.library.index?.games.count ?? 0
        AccessibilityNotification.Announcement("Library ready, \(LibraryRows.gameCount(count))").post()
    }
}

extension AppModel {
    fileprivate static let filesAndFoldersURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    )
}
