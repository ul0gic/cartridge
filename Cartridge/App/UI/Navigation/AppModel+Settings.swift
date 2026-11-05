import Foundation

enum SettingsRowID: Int, CaseIterable {
    case romFolder
    case rescan
    case bios
    case xboxBIOS
    case controller
    case introSound
    case interfaceSounds
    case about
}

extension AppModel {
    var isRescanning: Bool {
        guard let scan = dependencies.library.scan else { return false }
        return !scan.isFinished
    }

    var biosStatus: [BIOSRegion] {
        dependencies.bios.installedRegions
    }

    var xboxFirmwareInstalled: Set<XboxFirmwareFile> {
        dependencies.xboxFirmware.installed
    }

    var lastScan: (date: Date, games: Int)? {
        dependencies.library.index.map { ($0.scannedAt, $0.games.count) }
    }

    func isSoundOn(_ key: DefaultsKey) -> Bool {
        _ = soundSettingsVersion
        return UserDefaults.standard.object(forKey: key.rawValue) as? Bool ?? true
    }

    private func toggleSound(_ key: DefaultsKey) {
        UserDefaults.standard.set(!isSoundOn(key), forKey: key.rawValue)
        soundSettingsVersion += 1
    }

    func isSettingsRowEnabled(_ row: SettingsRowID) -> Bool {
        row != .rescan || !isRescanning
    }

    func handleSettings(_ event: NavigationEvent) {
        switch event.action {
        case .move(.up):
            moveSettings(-1)
        case .move(.down):
            moveSettings(1)
        case .confirm:
            activateSettings(SettingsRowID(rawValue: settingsFocus) ?? .romFolder)
        case .back:
            show(returnRoute)
        case .section(let direction):
            switchSection(direction)
        case .move, .options, .secondary, .pause, .text, .erase:
            break
        }
    }

    func handleAbout(_ event: NavigationEvent) {
        switch event.action {
        case .move(.up):
            aboutScroll = AboutScrollRequest(tick: aboutScroll.tick + 1, direction: -1)
        case .move(.down):
            aboutScroll = AboutScrollRequest(tick: aboutScroll.tick + 1, direction: 1)
        case .back:
            show(.settings)
            settingsFocus = SettingsRowID.about.rawValue
        case .move, .confirm, .options, .secondary, .pause, .section, .text, .erase:
            break
        }
    }

    func handleControllerGuide(_ event: NavigationEvent, tab: ControllerGuideTab) {
        switch event.action {
        case .move(.up):
            focusedButton = max(0, focusedButton - 1)
        case .move(.down):
            focusedButton = min(ControllerGuide.callouts(tab).count - 1, focusedButton + 1)
        case .section(.left) where tab != .menus:
            showGuide(tab == .xbox ? .games : .menus)
        case .section(.right) where tab != .xbox:
            showGuide(tab == .menus ? .games : .xbox)
        case .back:
            show(.settings)
            settingsFocus = SettingsRowID.controller.rawValue
        case .move, .confirm, .options, .secondary, .pause, .section, .text, .erase:
            break
        }
    }

    private func showGuide(_ tab: ControllerGuideTab) {
        show(.controller(tab))
        focusedButton = ControllerGuide.initialFocus(tab)
    }

    private func moveSettings(_ step: Int) {
        var index = settingsFocus + step
        while let row = SettingsRowID(rawValue: index) {
            if isSettingsRowEnabled(row) {
                settingsFocus = index
                return
            }
            index += step
        }
    }

    private func activateSettings(_ row: SettingsRowID) {
        switch row {
        case .romFolder: chooseROMFolder()
        case .rescan: rescanLibrary()
        case .bios: chooseBIOSFolder()
        case .xboxBIOS: chooseXboxFirmwareFolder()
        case .controller: show(.controller(.menus))
        case .introSound: toggleSound(.introSound)
        case .interfaceSounds: toggleSound(.interfaceSounds)
        case .about: show(.about)
        }
    }
}
