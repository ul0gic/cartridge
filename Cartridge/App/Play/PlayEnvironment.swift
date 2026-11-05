import AppKit
import Foundation

@MainActor
final class PlayEnvironment: PlayEnvironmentControlling {
    private static let fullScreenTimeout = Duration.seconds(3)

    private weak var window: NSWindow?
    private var enteredFullScreen = false
    private var cursorHidden = false
    private var activity: (any NSObjectProtocol)?

    func beginPlay(in window: NSWindow) async {
        guard self.window == nil else { return }
        self.window = window
        if !window.styleMask.contains(.fullScreen) {
            enteredFullScreen = await enterFullScreen(window)
        }
        NSCursor.hide()
        cursorHidden = true
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled],
            reason: "Playing"
        )
    }

    func endPlay() {
        guard let window else { return }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        if enteredFullScreen, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        enteredFullScreen = false
        self.window = nil
    }

    private func enterFullScreen(_ window: NSWindow) async -> Bool {
        let arrival = Task {
            for await _ in NotificationCenter.default.notifications(
                named: NSWindow.didEnterFullScreenNotification,
                object: window
            ) {
                return true
            }
            return false
        }
        let timeout = Task {
            try await Task.sleep(for: Self.fullScreenTimeout)
            arrival.cancel()
        }
        window.toggleFullScreen(nil)
        let entered = await arrival.value
        timeout.cancel()
        if !entered {
            PlayLog.session.error("full-screen-timeout")
        }
        return entered
    }
}
