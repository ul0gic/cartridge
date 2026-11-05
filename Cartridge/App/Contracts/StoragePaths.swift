import Foundation

enum StoragePaths {
    static let root = URL.applicationSupportDirectory.appending(path: "Cartridge", directoryHint: .isDirectory)
    static let libraryIndex = root.appending(path: "library.json", directoryHint: .notDirectory)
    static let favorites = root.appending(path: "favorites.json", directoryHint: .notDirectory)
    static let art = root.appending(path: "Art", directoryHint: .isDirectory)
    static let saves = root.appending(path: "Saves", directoryHint: .isDirectory)
    static let system = root.appending(path: "System", directoryHint: .isDirectory)
    static let scratch = root.appending(path: "Scratch", directoryHint: .isDirectory)
    static let gallery = root.appending(path: "Gallery", directoryHint: .isDirectory)
    static let cheats = root.appending(path: "Cheats", directoryHint: .isDirectory)
    static let galleryIndex = gallery.appending(path: "gallery.json", directoryHint: .notDirectory)
    static let galleryPartial = gallery.appending(path: ".partial", directoryHint: .isDirectory)
    static let xboxEEPROM = system.appending(path: "xbox-eeprom.bin", directoryHint: .notDirectory)
    static let xboxBaseDrive = system.appending(path: "xbox-base.img", directoryHint: .notDirectory)

    static func xboxFirmware(_ file: XboxFirmwareFile) -> URL {
        system.appending(path: file.rawValue, directoryHint: .notDirectory)
    }

    static func artFile(for id: GameID) -> URL {
        art.appending(path: id.system.rawValue, directoryHint: .isDirectory)
            .appending(path: "\(id.identity.string).png", directoryHint: .notDirectory)
    }

    static func backdropFile(for id: GameID) -> URL {
        art.appending(path: id.system.rawValue, directoryHint: .isDirectory)
            .appending(path: "\(id.identity.string)-backdrop.png", directoryHint: .notDirectory)
    }

    static func saveFolder(for id: GameID) -> URL {
        saves.appending(path: id.saveFolderName, directoryHint: .isDirectory)
    }

    static func xboxGameDrive(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "xbox-drive.qcow2", directoryHint: .notDirectory)
    }

    static func batterySave(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "battery.srm", directoryHint: .notDirectory)
    }

    static func manualState(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "state-manual.state", directoryHint: .notDirectory)
    }

    static func resumeState(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "state-resume.state", directoryHint: .notDirectory)
    }

    static func resumeSnapshot(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "resume.png", directoryHint: .notDirectory)
    }

    static func playRecord(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "play.json", directoryHint: .notDirectory)
    }

    static func slotState(_ slot: SlotNumber, for id: GameID) -> URL {
        slotsFolder(for: id).appending(path: "\(slot.fileStem).state", directoryHint: .notDirectory)
    }

    static func slotThumbnail(_ slot: SlotNumber, for id: GameID) -> URL {
        slotsFolder(for: id).appending(path: "\(slot.fileStem).png", directoryHint: .notDirectory)
    }

    static func slotStaging(_ slot: SlotNumber, for id: GameID) -> (state: URL, thumbnail: URL) {
        let stem = String(format: ".staging-%02d", slot.value)
        let folder = slotsFolder(for: id)
        return (
            folder.appending(path: "\(stem).state", directoryHint: .notDirectory),
            folder.appending(path: "\(stem).png", directoryHint: .notDirectory)
        )
    }

    static func slotIndex(for id: GameID) -> URL {
        slotsFolder(for: id).appending(path: "slots.json", directoryHint: .notDirectory)
    }

    static func cheatSettings(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "cheats.json", directoryHint: .notDirectory)
    }

    static func backupsFolder(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "backups", directoryHint: .isDirectory)
    }

    private static func slotsFolder(for id: GameID) -> URL {
        saveFolder(for: id).appending(path: "slots", directoryHint: .isDirectory)
    }

    static func scratchFolder(for sessionToken: String) -> URL {
        scratch.appending(path: sessionToken, directoryHint: .isDirectory)
    }
}
