import AppKit
import GameController
import Observation

@MainActor
@Observable
final class ControllerMonitor: ControllerMonitoring {
    private(set) var connected: ControllerInfo?
    private(set) var menuTilt = MenuTilt.zero

    var mode = InputMode.navigation {
        didSet { resetHeldInput() }
    }

    var playSink: (any PlayInputSink)? {
        didSet { router.setSink(playSink) }
    }

    var handler: ((NavigationEvent) -> Void)?

    var triggerRole = TriggerRole.gameButtons {
        didSet { router.setTriggerRole(triggerRole) }
    }

    var faceLayout = FaceLayout.positional {
        didSet { router.setFaceLayout(faceLayout) }
    }

    var playControlHandler: ((PlayControlEvent) -> Void)?

    @ObservationIgnored private let router: ControllerInputRouter
    @ObservationIgnored private let routerEvents: AsyncStream<RouterEvent>
    @ObservationIgnored private let handlerQueue: DispatchQueue
    @ObservationIgnored private let repeater = DirectionRepeater(source: .controller)
    @ObservationIgnored private let keyboard = KeyboardMonitor()
    @ObservationIgnored private let hid = HIDTransportProbe()
    @ObservationIgnored private var attached: GCController?
    @ObservationIgnored private let feel = ControllerFeel()
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private let log = LogChannel(category: "input")

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: RouterEvent.self)
        let queue = DispatchQueue(label: "io.corelift.Cartridge.controller", qos: .userInteractive)
        handlerQueue = queue
        routerEvents = stream
        router = ControllerInputRouter(events: continuation, queue: queue)
        repeater.onEvent = { [weak self] in self?.handler?($0) }
        keyboard.onEvent = { [weak self] in self?.handler?($0) }
        hid.onChange = { [weak self] in self?.refreshConnected() }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshControllers() }
            })
        }
        // The framework stops delivering input when the app is inactive, so a held direction never sees its release.
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetHeldInput() }
            })
        }
        eventTask = Task { [weak self, routerEvents] in
            for await event in routerEvents {
                self?.receive(event)
            }
        }
        hid.start()
        keyboard.start()
        refreshControllers()
    }

    func glyphName(for action: NavigationAction) -> String? {
        guard let gamepad = attached?.extendedGamepad else { return nil }
        let element: GCControllerElement? = switch action {
        case .move(let direction): Self.dpadElement(direction, in: gamepad)
        case .confirm: gamepad.buttonA
        case .back: gamepad.buttonB
        case .options: gamepad.buttonMenu
        case .secondary: gamepad.buttonY
        case .pause: gamepad.touchpadClick
        case .section(.left): gamepad.leftShoulder
        case .section(.right): gamepad.rightShoulder
        case .section(.up), .section(.down), .text, .erase: nil
        }
        return element?.sfSymbolsName
    }

    private static func dpadElement(_ direction: Direction, in gamepad: GCExtendedGamepad) -> GCControllerElement {
        switch direction {
        case .up: gamepad.dpad.up
        case .down: gamepad.dpad.down
        case .left: gamepad.dpad.left
        case .right: gamepad.dpad.right
        }
    }

    private func resetHeldInput() {
        router.setMode(mode, leftStick: attached?.extendedGamepad?.leftThumbstick)
        keyboard.mode = mode
        repeater.releaseAll()
        menuTilt = .zero
    }

    private func receive(_ event: RouterEvent) {
        switch event {
        case .directionPressed(let direction):
            repeater.press(direction)
        case .directionReleased(let direction):
            repeater.release(direction)
        case .action(let action):
            handler?(NavigationEvent(action: action, source: .controller, isRepeat: false))
        case .playControl(let event):
            playControlHandler?(event)
        case .tilt(let tilt):
            if tilt != menuTilt {
                menuTilt = tilt
            }
        }
    }

    func feedback(_ kind: FeedbackKind) {
        feel.play(kind)
    }

    func setLight(red: Float, green: Float, blue: Float) {
        feel.setLight(red: red, green: green, blue: blue)
    }

    private func refreshControllers() {
        let primary = GCController.controllers().first { $0.extendedGamepad != nil }
        if primary !== attached {
            if let old = attached?.extendedGamepad {
                router.detach(old)
            }
            repeater.releaseAll()
            attached = primary
            feel.attach(primary)
            if let primary, let gamepad = primary.extendedGamepad {
                primary.handlerQueue = handlerQueue
                router.attach(gamepad)
            }
        }
        refreshConnected()
    }

    private func refreshConnected() {
        let info = attached.map { ControllerInfo(name: $0.productCategory, transport: hid.transport) }
        guard info != connected else { return }
        connected = info
        if let info {
            log.info(
                """
                controller connected name="\(info.name)" transport=\(info.transport.logName) \
                \(Self.batteryDescription(attached?.battery))
                """
            )
        } else {
            log.info("controller disconnected")
        }
    }
}

extension ControllerMonitor {
    fileprivate static func batteryDescription(_ battery: GCDeviceBattery?) -> String {
        guard let battery else { return "battery=unknown" }
        let state = switch battery.batteryState {
        case .discharging: "discharging"
        case .charging: "charging"
        case .full: "full"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
        return "battery=\(Int((battery.batteryLevel * 100).rounded()))% battery-state=\(state)"
    }
}

extension ControllerTransport {
    fileprivate var logName: String {
        switch self {
        case .bluetooth: "bluetooth"
        case .usb: "usb"
        case .unknown: "unknown"
        }
    }
}
