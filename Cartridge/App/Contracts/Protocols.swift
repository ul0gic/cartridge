import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
protocol LibraryStoring: AnyObject, Observable {
    var index: LibraryIndex? { get }
    var scan: ScanProgress? { get }
    var error: LibraryError? { get }

    func load() async
    func chooseFolder(_ url: URL) async
    func rescan() async
    func retry() async
    func games(in system: GameSystem) -> [GameRecord]
    func continuePlaying() -> [GameRecord]
    func favorites() -> [GameRecord]
    func isFavorite(_ id: GameID) -> Bool
    func setFavorite(_ isFavorite: Bool, for id: GameID)
    func playRecord(for id: GameID) -> PlayRecord?
    func metadata(for game: GameRecord) -> GameMetadata?
    func recordPlay(_ record: PlayRecord, for id: GameID) async
    func saveSelection(_ selection: LibrarySelection)
    func protectedLocation(of url: URL) -> ProtectedLocation?
}

protocol ArtProviding: AnyObject, Sendable {
    func cachedArtURL(for game: GameRecord) -> URL?
    func requestArt(for game: GameRecord) async -> ArtStatus
    func cachedBackdropURL(for game: GameRecord) -> URL?
    func requestBackdrop(for game: GameRecord) async -> URL?
}

@MainActor
protocol BIOSStoring: AnyObject, Observable {
    var installedRegions: [BIOSRegion] { get }
    var isReady: Bool { get }

    func importBIOS(from folder: URL) async -> BIOSImportResult
}

@MainActor
protocol XboxFirmwareStoring: AnyObject, Observable {
    var installed: Set<XboxFirmwareFile> { get }
    var isReady: Bool { get }

    func importFirmware(from folder: URL) async -> XboxFirmwareImport
}

@MainActor
protocol PlaySessionControlling: AnyObject, Observable {
    var game: GameRecord { get }
    var state: PlaySessionState { get }
    var geometry: FrameGeometry? { get }
    var stats: PlayStats? { get }
    var discIndex: Int { get }
    var discCount: Int { get }
    var inputSink: any PlayInputSink { get }
    var frameView: AnyView { get }
    var start: SessionStart { get }
    var look: DisplayLook { get set }
    var requestedSpeed: PlaySpeed { get }
    var activeSpeed: ActiveSpeed? { get }
    var captureSink: (any CaptureFrameSink)? { get set }
    var audioTap: SessionAudioTap? { get }
    var holdsFirstFrame: Bool { get set }

    func start() async
    func pause()
    func resume()
    func reset() async
    func changeDisc(to index: Int) async throws
    func quitToLibrary() async throws -> QuitOutcome
    func quitWithoutSaving() async
    func cancel()
    func setSpeed(_ speed: PlaySpeed)
    func saveState(to url: URL) async throws
    func loadState(from url: URL) async throws
    func writeSnapshot(to url: URL) -> Bool
    func setCheats(_ codes: [String]) async throws
    func releaseFirstFrame() async
    func batterySaveSize() async -> Int
    func flushBatterySave() async throws -> Bool
}

protocol PlaySessionFactory: AnyObject, Sendable {
    @MainActor
    func makeSession(
        for game: GameRecord,
        playRecord: PlayRecord?,
        withoutBIOS: Bool,
        start: SessionStart,
        look: DisplayLook
    ) -> any PlaySessionControlling
}

@MainActor
protocol PlayEnvironmentControlling: AnyObject {
    func beginPlay(in window: NSWindow) async
    func endPlay()
}

@MainActor
protocol ControllerMonitoring: AnyObject, Observable {
    var connected: ControllerInfo? { get }
    var menuTilt: MenuTilt { get }
    var mode: InputMode { get set }
    var playSink: (any PlayInputSink)? { get set }
    var handler: ((NavigationEvent) -> Void)? { get set }
    var triggerRole: TriggerRole { get set }
    var faceLayout: FaceLayout { get set }
    var playControlHandler: ((PlayControlEvent) -> Void)? { get set }

    func glyphName(for action: NavigationAction) -> String?
    func feedback(_ kind: FeedbackKind)
    func setLight(red: Float, green: Float, blue: Float)
}

@MainActor
protocol AppLifecycleHandling: AnyObject {
    func prepareToTerminate() async
}
