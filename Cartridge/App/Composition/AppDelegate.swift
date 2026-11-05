import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var lifecycleHandler: (any AppLifecycleHandling)?

    nonisolated private static let log = LogChannel(category: "lifecycle")

    private var observers: [any NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.log.notice(
            """
            launch pid=\(getpid()) \(SystemConditions.build) display-hz=\(SystemConditions.displayHz) \
            \(SystemConditions.power)
            """
        )
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { "will-sleep" }
        observe(workspace, NSWorkspace.didWakeNotification) { "did-wake \(SystemConditions.power)" }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { "screens-did-sleep" }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { "screens-did-wake" }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { "space-changed \(SystemConditions.focus)" }
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Self.log.notice("frontmost-changed app=\(app?.bundleIdentifier ?? "unknown")")
        })
        let center = NotificationCenter.default
        observe(center, NSApplication.didChangeScreenParametersNotification) {
            "screens-changed count=\(NSScreen.screens.count) main-hz=\(SystemConditions.displayHz)"
        }
        observe(center, NSWindow.didChangeScreenNotification) {
            let screen = NSApplication.shared.mainWindow?.screen
            let hz = screen.map { String($0.maximumFramesPerSecond) } ?? "unknown"
            return "window-screen-changed name=\"\(screen?.localizedName ?? "unknown")\" hz=\(hz)"
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.log.notice("become-active")
    }

    func applicationDidResignActive(_ notification: Notification) {
        Self.log.notice("resign-active \(SystemConditions.focus)")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let handler = Self.lifecycleHandler else { return .terminateNow }
        Task {
            await handler.prepareToTerminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.log.notice("terminate")
        LogFile.shared.flush()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        message: @escaping @MainActor () -> String
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Self.log.notice(message())
            }
        })
    }
}
