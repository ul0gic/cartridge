import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        WindowObservingView(model: model)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class WindowObservingView: NSView {
    private let model: AppModel
    private var observers: [any NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidMoveToWindow() {
        guard let window, observers.isEmpty else { return }
        window.collectionBehavior.insert(.fullScreenPrimary)
        model.attach(window: window)
        observe(NSWindow.didEnterFullScreenNotification, in: window) { [weak self] in
            self?.model.windowDidChangeFullScreen(true)
        }
        observe(NSWindow.didExitFullScreenNotification, in: window) { [weak self] in
            self?.model.windowDidChangeFullScreen(false)
        }
        observe(NSWindow.didResizeNotification, in: window) { [weak self] in
            self?.reportSafeTop(of: window)
        }
        reportSafeTop(of: window)
        let wantsFullScreen = UserDefaults.standard.object(forKey: DefaultsKey.lastFullScreen.rawValue) as? Bool ?? true
        if wantsFullScreen, !window.styleMask.contains(.fullScreen) {
            Task { window.toggleFullScreen(nil) }
        }
    }

    private func observe(_ name: Notification.Name, in window: NSWindow, _ action: @escaping @MainActor () -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append(token)
    }

    private func reportSafeTop(of window: NSWindow) {
        model.measuredSafeTop(window.contentView?.safeAreaInsets.top ?? 0)
    }
}
