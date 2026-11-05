import AppKit
import Observation
import SwiftUI

enum PanelPhase: Equatable {
    case idle
    case starting
    case failed(PlayError)
    case slots(PanelSlots)
}

struct AboutScrollRequest: Equatable {
    var tick = 0
    var direction = 0
}

enum HomeState: Equatable {
    case browse
    case empty(FolderSummary)
    case missing(FolderSummary)
}

struct FolderSummary: Equatable {
    let name: String
    let path: String
    var fileCount = 0
}

@MainActor
@Observable
final class AppModel: AppLifecycleHandling {
    private(set) var route = Route.launch
    private(set) var introSkips = 0
    private(set) var isAwaitingLibrary = false
    private(set) var safeTop = Layout.titlebarHeight
    private(set) var isFullScreen = false
    var cursor = LibraryCursor()
    var shell = ShellState()
    var focusedButton = 0
    var animatesScroll = true
    var crashedGameTitle: String?
    var biosResult: BIOSImportResult?
    var xboxFirmwareImport: XboxFirmwareImport?
    var panelPhase = PanelPhase.idle
    var isFadingToBlack = false
    var insert: CartridgeInsert?
    var session: (any PlaySessionControlling)?
    var hub: HubModel?
    var captureMenu: CaptureMenuModel?
    var playChips: PlayChipsModel?
    var settingsFocus = 0
    var aboutScroll = AboutScrollRequest()
    var soundSettingsVersion = 0

    @ObservationIgnored let dependencies: AppDependencies
    @ObservationIgnored let log = LogChannel(category: "library")
    @ObservationIgnored var isPickerOpen = false
    @ObservationIgnored var isForegroundScan = false
    @ObservationIgnored var fullScreenBeforePlay: Bool?
    @ObservationIgnored var pauseRequestedAt: ContinuousClock.Instant?
    @ObservationIgnored var crashedAt: ContinuousClock.Instant?
    @ObservationIgnored var sessionWatcher: Task<Void, Never>?
    @ObservationIgnored private let coordinator: ArtCoordinator
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?
    @ObservationIgnored private var hasLoggedReady = false
    @ObservationIgnored private var introDone = false
    @ObservationIgnored private var pendingRoute: Route?
    @ObservationIgnored private var measuredTop: CGFloat = 0
    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored var controllerWatcher: Task<Void, Never>?
    @ObservationIgnored var activationObservers: [any NSObjectProtocol] = []
    @ObservationIgnored var isPausedForBackground = false
    @ObservationIgnored var recorder: CaptureRecorder?
    @ObservationIgnored var sessionCheats: SessionCheats?
    @ObservationIgnored var isCapturePause = false
    @ObservationIgnored var sessionWithoutBIOS = false
    @ObservationIgnored var restart: (reason: RestartReason, began: ContinuousClock.Instant)?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        coordinator = ArtCoordinator(art: dependencies.art, launchedAt: .now)
    }

    var chrome: ChromeState {
        ChromeState(
            controller: dependencies.controller.connected,
            glyphs: HintGlyphs.resolve(from: dependencies.controller),
            safeTop: safeTop
        )
    }

    var rows: [LibraryRow] {
        LibraryRows.rows(from: dependencies.library)
    }

    var scan: ScanProgress? {
        dependencies.library.scan
    }

    var folderPath: String {
        dependencies.library.index?.romFolderPath ?? dependencies.library.scan?.folderPath ?? ""
    }

    var homeState: HomeState {
        let library = dependencies.library
        switch library.error {
        case .folderMissing(let path), .notAFolder(let path):
            return .missing(FolderSummary(name: Self.folderName(of: path), path: Self.abbreviated(path)))
        case .accessDenied, .indexUnreadable, nil:
            break
        }
        if let index = library.index, index.games.isEmpty, library.scan == nil {
            return .empty(FolderSummary(
                name: Self.folderName(of: index.romFolderPath),
                path: Self.abbreviated(index.romFolderPath),
                fileCount: index.fileCount
            ))
        }
        return .browse
    }

    var deniedFolder: FolderSummary {
        let error = dependencies.library.error
        guard case .accessDenied(let path, _) = error else {
            return FolderSummary(name: "your ROM folder", path: "")
        }
        var name = Self.folderName(of: path)
        if case .accessDenied(_, let location?) = error {
            name = location.displayName
        }
        return FolderSummary(name: name, path: Self.abbreviated(path))
    }

    var isMenuEnabled: Bool {
        switch route {
        case .launch, .play: false
        case .welcome, .denied, .scanning, .library, .gamePanel, .settings, .about, .controller: true
        }
    }

    var canOpenSettings: Bool {
        route == .library || route == .scanning
    }

    var canRescan: Bool {
        isMenuEnabled && dependencies.library.index != nil && dependencies.library.scan == nil
    }

    static func folderName(of path: String) -> String {
        URL(filePath: path).lastPathComponent
    }

    static func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    func start() async {
        guard startedAt == nil else { return }
        startedAt = .now
        dependencies.controller.handler = { [weak self] in self?.handle($0) }
        dependencies.controller.mode = .navigation
        dependencies.controller.playControlHandler = { [weak self] in self?.handlePlayControl($0) }
        watchController()
        watchActivation()
        guard UserDefaults.standard.string(forKey: DefaultsKey.romFolderPath.rawValue) != nil else {
            deliver(.welcome)
            return
        }
        await dependencies.library.load()
        logLibraryLoaded()
        deliver(settledRoute)
    }

    func skipIntro() {
        introSkips += 1
    }

    func introDidFinish() {
        guard !introDone else { return }
        introDone = true
        if let pendingRoute {
            show(pendingRoute)
        } else {
            isAwaitingLibrary = true
        }
    }

    private func deliver(_ route: Route) {
        if introDone {
            show(route)
        } else {
            pendingRoute = route
        }
    }

    func attach(window: NSWindow) {
        self.window = window
    }

    func windowDidChangeFullScreen(_ isFullScreen: Bool) {
        self.isFullScreen = isFullScreen
        updateSafeTop()
    }

    func measuredSafeTop(_ top: CGFloat) {
        measuredTop = top
        updateSafeTop()
    }

    func tileArt(for game: GameRecord) async -> TileArt {
        await coordinator.tileArt(for: game)
    }

    func ambientColors(for game: GameRecord) async -> AmbientColors {
        await coordinator.ambientColors(for: game)
    }

    func backdrop(for game: GameRecord) async -> BackdropSource {
        await coordinator.backdrop(for: game)
    }

    func metadata(for game: GameRecord) -> GameMetadata? {
        dependencies.library.metadata(for: game)
    }

    func resumeDate(for game: GameRecord) -> Date? {
        dependencies.library.playRecord(for: game.id)?.resumeStateAt
    }

    func dismissCrashBand() {
        withAnimation(Motion.easeOut(Motion.band)) {
            crashedGameTitle = nil
        }
    }

    func show(_ route: Route) {
        self.route = route
        focusedButton = 0
        settingsFocus = 0
        if !route.keepsBIOSResult {
            biosResult = nil
            xboxFirmwareImport = nil
        }
        if route == .library || route == .scanning {
            restoreSelectionIfNeeded()
            logReadyIfNeeded()
        }
    }

    func settle() {
        show(settledRoute)
    }

    private var settledRoute: Route {
        if case .accessDenied = dependencies.library.error {
            return .denied
        }
        return .library
    }

    private func logLibraryLoaded() {
        guard let startedAt, let index = dependencies.library.index else { return }
        let milliseconds = Int(startedAt.duration(to: .now).seconds * 1000)
        log.info("library-loaded ms=\(milliseconds) games=\(index.games.count)")
    }

    private func restoreSelectionIfNeeded() {
        guard cursor.slot(in: rows) == nil,
              let selection = dependencies.library.index?.lastSelection
        else { return }
        cursor.restore(selection, in: rows)
    }

    private func logReadyIfNeeded() {
        guard !hasLoggedReady, route == .library, let startedAt, let index = dependencies.library.index else { return }
        hasLoggedReady = true
        let elapsed = startedAt.duration(to: .now)
        let milliseconds = Int(elapsed.seconds * 1000)
        log.info("ready ms=\(milliseconds) games=\(index.games.count)")
    }

    private func updateSafeTop() {
        let isFull = window?.styleMask.contains(.fullScreen) ?? isFullScreen
        safeTop = isFull ? measuredTop : max(measuredTop, Layout.titlebarHeight)
    }
}
