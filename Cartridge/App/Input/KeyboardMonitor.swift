import AppKit
import Carbon.HIToolbox

@MainActor
final class KeyboardMonitor {
    var mode: InputMode = .navigation {
        didSet { repeater.releaseAll() }
    }

    var onEvent: ((NavigationEvent) -> Void)? {
        didSet { repeater.onEvent = onEvent }
    }

    private let repeater = DirectionRepeater(source: .keyboard)
    private var observers: [any NSObjectProtocol] = []
    private var monitor: Any?

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
        let resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.repeater.releaseAll() }
        }
        observers.append(resign)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !event.modifierFlags.contains(.command), !(event.window is NSPanel),
              let key = Key(event: event)
        else { return event }
        if event.type == .keyUp {
            if case .arrow(let direction) = key {
                repeater.release(direction)
            }
            return nil
        }
        guard !event.isARepeat else { return nil }
        switch (key, mode) {
        case (.escape, .navigation):
            emit(.back)
        case (.escape, .play):
            emit(.pause)
        case (.arrow(let direction), .navigation):
            repeater.press(direction)
        case (.action(let action), .navigation):
            emit(action)
        case (.arrow, .play), (.action, .play):
            break
        }
        return nil
    }

    private func emit(_ action: NavigationAction) {
        onEvent?(NavigationEvent(action: action, source: .keyboard, isRepeat: false))
    }

    private enum Key {
        case arrow(Direction)
        case escape
        case action(NavigationAction)

        private static let arrows: [Int: Direction] = [
            kVK_LeftArrow: .left, kVK_RightArrow: .right, kVK_UpArrow: .up, kVK_DownArrow: .down,
        ]

        init?(event: NSEvent) {
            let code = Int(event.keyCode)
            if let direction = Self.arrows[code] {
                self = .arrow(direction)
                return
            }
            switch code {
            case kVK_Return: self = .action(.confirm)
            case kVK_Escape: self = .escape
            case kVK_Tab: self = .action(.section(event.modifierFlags.contains(.shift) ? .left : .right))
            case kVK_Delete: self = .action(.erase)
            case kVK_ANSI_Period: self = .action(.secondary)
            default:
                guard let text = Self.searchText(event) else { return nil }
                self = .action(.text(text))
            }
        }

        private static let symbols = CharacterSet(charactersIn: " -:?+")

        private static func searchText(_ event: NSEvent) -> String? {
            guard event.modifierFlags.isDisjoint(with: [.control, .option]),
                  let text = event.charactersIgnoringModifiers, text.count == 1,
                  text.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || symbols.contains($0) })
            else { return nil }
            return text.uppercased()
        }
    }
}
