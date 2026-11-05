import Foundation
import Observation

struct ViewerMessage: Equatable {
    enum Kind {
        case ok
        case warning
        case danger
    }

    let kind: Kind
    let head: String
    let detail: String?
}

@MainActor
@Observable
final class GalleryViewerModel {
    enum Button {
        case playPause
        case makeGIF
        case showInFinder
        case delete
    }

    enum Exit {
        case closed
        case deleted
    }

    private static let idleDelay: Duration = .milliseconds(3000)
    private static let gifSecondsPerClipSecond = 1.5
    private static let gifEstimateStep = 10.0
    private static let gifEstimateMinuteThreshold = 90.0

    let item: CaptureItem
    let isMissing: Bool
    let buttons: [Button]
    let player: ClipPlayer?
    private(set) var focus = 0
    private(set) var isDeleteArmed = false
    private(set) var isMakingGIF = false
    private(set) var message: ViewerMessage?
    private(set) var platesVisible = true

    @ObservationIgnored private let store: GalleryStore
    @ObservationIgnored private var armTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    init(item: CaptureItem, store: GalleryStore) {
        self.item = item
        self.store = store
        let url = store.url(of: item)
        isMissing = !FileManager.default.fileExists(atPath: url.path)
        if isMissing {
            buttons = [.delete]
            player = nil
            message = ViewerMessage(
                kind: .warning,
                head: "Can’t find this file",
                detail: "It was moved or deleted outside Cartridge. Delete removes it from the Gallery."
            )
        } else if item.kind == .clip {
            buttons = [.playPause, .makeGIF, .showInFinder, .delete]
            player = ClipPlayer(url: url, total: item.durationSeconds ?? 0)
        } else {
            buttons = [.showInFinder, .delete]
            player = nil
        }
        player?.onEnded = { [weak self] in self?.showPlates() }
        player?.play()
        restartIdleTimer()
    }

    var gifEstimate: String {
        let clipSeconds = item.durationSeconds ?? 0
        let seconds = max(
            Self.gifEstimateStep,
            (clipSeconds / Self.gifSecondsPerClipSecond / Self.gifEstimateStep).rounded(.up) * Self.gifEstimateStep
        )
        guard seconds > Self.gifEstimateMinuteThreshold else { return "About \(Int(seconds)) seconds" }
        return "About \(Int((seconds / 60).rounded(.up))) minutes"
    }

    func handle(_ action: NavigationAction) -> Exit? {
        let wasHidden = !platesVisible
        showPlates()
        guard !wasHidden else { return nil }
        if message?.kind == .danger {
            message = nil
        }
        switch action {
        case .move(.left):
            moveFocus(to: max(0, focus - 1))
        case .move(.right):
            moveFocus(to: min(buttons.count - 1, focus + 1))
        case .confirm:
            return activate(buttons[focus])
        case .back:
            return .closed
        case .move, .options, .secondary, .pause, .section, .text, .erase:
            break
        }
        return nil
    }

    func stop() {
        player?.stop()
        armTask?.cancel()
        idleTask?.cancel()
        messageTask?.cancel()
    }

    private func moveFocus(to target: Int) {
        guard target != focus else { return }
        focus = target
        disarm()
    }

    private func activate(_ button: Button) -> Exit? {
        switch button {
        case .playPause:
            player?.toggle()
            restartIdleTimer()
        case .makeGIF:
            makeGIF()
        case .showInFinder:
            store.revealInFinder(item.id)
        case .delete:
            if isMissing || isDeleteArmed {
                return delete()
            }
            arm()
        }
        return nil
    }

    private func arm() {
        isDeleteArmed = true
        message = ViewerMessage(
            kind: .warning,
            head: "Delete this \(item.noun)?",
            detail: "It’s removed from the Gallery and deleted from your Mac."
        )
        armTask?.cancel()
        armTask = Task {
            do {
                try await Task.sleep(for: Motion.confirmArm)
            } catch {
                return
            }
            disarm()
        }
    }

    private func disarm() {
        armTask?.cancel()
        guard isDeleteArmed else { return }
        isDeleteArmed = false
        message = nil
    }

    private func delete() -> Exit? {
        do throws(GalleryError) {
            try store.delete(item.id)
        } catch {
            disarm()
            message = ViewerMessage(
                kind: .danger,
                head: "Couldn’t delete this \(item.noun)",
                detail: "The file couldn’t be removed. It’s still in the Gallery."
            )
            return nil
        }
        stop()
        return .deleted
    }

    private func makeGIF() {
        guard !isMakingGIF else { return }
        player?.pause()
        restartIdleTimer()
        isMakingGIF = true
        message = nil
        Task {
            do throws(GalleryError) {
                let made = try await store.makeGIF(from: item.id)
                finishGIF(ViewerMessage(kind: .ok, head: "GIF added to the Gallery", detail: made.fileName))
            } catch {
                let detail = error == .diskFull
                    ? "Your Mac is out of disk space. The clip is still in the Gallery."
                    : "The clip couldn’t be read. It’s still in the Gallery."
                finishGIF(ViewerMessage(kind: .danger, head: "Couldn’t make the GIF", detail: detail))
            }
        }
    }

    private func finishGIF(_ result: ViewerMessage) {
        isMakingGIF = false
        message = result
        messageTask?.cancel()
        guard result.kind == .ok else { return }
        messageTask = Task {
            do {
                try await Task.sleep(for: Motion.chipHold)
            } catch {
                return
            }
            message = nil
        }
    }

    private func showPlates() {
        platesVisible = true
        restartIdleTimer()
    }

    private func restartIdleTimer() {
        idleTask?.cancel()
        guard player?.isPlaying == true else { return }
        idleTask = Task {
            do {
                try await Task.sleep(for: Self.idleDelay)
            } catch {
                return
            }
            platesVisible = false
        }
    }
}
