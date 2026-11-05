struct AppDependencies {
    let library: any LibraryStoring
    let art: any ArtProviding
    let bios: any BIOSStoring
    let xboxFirmware: any XboxFirmwareStoring
    let sessions: any PlaySessionFactory
    let environment: any PlayEnvironmentControlling
    let controller: any ControllerMonitoring
    let slots: SlotStore
    let cheatSettings: CheatSettingsStore
    let backups: SaveBackupStore
    let looks: LookStore
    let gallery: GalleryStore
    let cheats: CheatDatabase
}
