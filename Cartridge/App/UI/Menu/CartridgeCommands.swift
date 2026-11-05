import SwiftUI

struct CartridgeCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Cartridge") { model.showAbout() }
                .disabled(!model.isMenuEnabled)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.showSettings() }
                .keyboardShortcut(",")
                .disabled(!model.canOpenSettings)
        }
        CommandGroup(replacing: .newItem) {
            Button("Choose ROM Folder…") { model.chooseROMFolder() }
                .keyboardShortcut("o")
                .disabled(!model.isMenuEnabled)
            Button("Rescan Library") { model.rescanLibrary() }
                .keyboardShortcut("r")
                .disabled(!model.canRescan)
            Button("Choose PS1 BIOS Folder…") { model.chooseBIOSFolder() }
                .disabled(!model.isMenuEnabled)
            Button("Choose Xbox BIOS Folder…") { model.chooseXboxFirmwareFolder() }
                .disabled(!model.isMenuEnabled)
        }
    }
}
