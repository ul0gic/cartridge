import Foundation

extension PlaySession {
    func xboxStartOptions() throws -> [String: String] {
        guard game.system == .xbox else { return [:] }
        let configDirectory = StoragePaths.scratchFolder(for: token)
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        } catch {
            PlayLog.session.error("directory-create-failed \(error.localizedDescription)")
            throw PlayError.contentUnreadable
        }
        let restores = switch start {
        case .slot: true
        case .resume: playRecord.resumeStateAt != nil
        case .fresh: false
        }
        return [
            XboxStartOption.bootROMPath.rawValue: StoragePaths.xboxFirmware(.bootROM).path,
            XboxStartOption.flashPath.rawValue: StoragePaths.xboxFirmware(.flash).path,
            XboxStartOption.eepromPath.rawValue: StoragePaths.xboxEEPROM.path,
            XboxStartOption.baseDrivePath.rawValue: StoragePaths.xboxBaseDrive.path,
            XboxStartOption.gameDrivePath.rawValue: StoragePaths.xboxGameDrive(for: game.id).path,
            XboxStartOption.configDirectory.rawValue: configDirectory.path,
            XboxStartOption.boot.rawValue: (restores ? XboxBootMode.restore : XboxBootMode.fresh).rawValue,
        ]
    }
}
