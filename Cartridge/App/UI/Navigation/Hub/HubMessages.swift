import Foundation
import Observation

enum HubMessageKind: Equatable {
    case ok
    case warn
    case danger
    case info
}

struct HubMessage: Equatable {
    let kind: HubMessageKind
    let head: String
    var detail: String?
    var glyph: String?
    var showsNoController = false
    var showsSpinner = false
    var hold: Duration?

    static func ok(_ head: String, _ detail: String? = nil) -> HubMessage {
        HubMessage(kind: .ok, head: head, detail: detail, hold: Motion.chipHold)
    }

    static func warn(_ head: String, _ detail: String? = nil) -> HubMessage {
        HubMessage(kind: .warn, head: head, detail: detail)
    }

    static func danger(_ head: String, _ detail: String? = nil) -> HubMessage {
        HubMessage(kind: .danger, head: head, detail: detail)
    }

    static func info(_ head: String, _ detail: String? = nil, glyph: String = "info.circle") -> HubMessage {
        HubMessage(kind: .info, head: head, detail: detail, glyph: glyph)
    }

    static let disconnected = HubMessage(
        kind: .warn,
        head: "Controller disconnected",
        detail: "Reconnect it, or use the keyboard.",
        showsNoController: true
    )
}

@MainActor
@Observable
final class HubMessageBox {
    private(set) var current: HubMessage?

    @ObservationIgnored private var holdTask: Task<Void, Never>?

    func show(_ message: HubMessage) {
        holdTask?.cancel()
        current = message
        guard let hold = message.hold else { return }
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled, self?.current == message else { return }
            self?.current = nil
        }
    }

    func clear() {
        holdTask?.cancel()
        current = nil
    }

    func clearWarning() {
        if current?.kind == .warn {
            clear()
        }
    }
}

@MainActor
@Observable
final class Arming<ID: Hashable> {
    private(set) var armed: ID?

    @ObservationIgnored private let messages: HubMessageBox
    @ObservationIgnored private var task: Task<Void, Never>?

    init(messages: HubMessageBox) {
        self.messages = messages
    }

    func isArmed(_ id: ID) -> Bool {
        armed == id
    }

    func arm(_ id: ID, message: HubMessage? = nil) {
        task?.cancel()
        armed = id
        if let message {
            messages.show(message)
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: Motion.confirmArm)
            guard !Task.isCancelled else { return }
            self?.disarm()
        }
    }

    func disarm() {
        task?.cancel()
        task = nil
        armed = nil
        messages.clearWarning()
    }
}
