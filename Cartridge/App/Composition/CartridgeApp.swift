import SwiftUI

@main
struct CartridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let library = LibraryStore()
        let gallery = GalleryStore()
        let dependencies = AppDependencies(
            library: library,
            art: ArtStore(library: library),
            bios: BIOSStore(),
            xboxFirmware: XboxFirmwareStore(),
            sessions: PlaySessionFactoryImpl(library: library),
            environment: PlayEnvironment(),
            controller: ControllerMonitor(),
            slots: SlotStore(),
            cheatSettings: CheatSettingsStore(),
            backups: SaveBackupStore(),
            looks: LookStore(),
            gallery: gallery,
            cheats: CheatDatabase()
        )
        Task { await gallery.load() }
        _model = State(initialValue: AppModel(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup("Cartridge") {
            RootView(model: model)
                .frame(minWidth: 1280, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { CartridgeCommands(model: model) }
    }
}
