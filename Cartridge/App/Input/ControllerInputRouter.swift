import GameController
import os

enum RouterEvent: Sendable {
    case directionPressed(Direction)
    case directionReleased(Direction)
    case action(NavigationAction)
    case playControl(PlayControlEvent)
    case tilt(MenuTilt)
}

final class ControllerInputRouter: Sendable {
    private enum CreatePhase {
        case idle
        case timing
        case spent
    }

    private enum PendingTimer: Sendable {
        case captureHold(UInt64)
        case selectTap(UInt64)
    }

    private struct State {
        var mode = InputMode.navigation
        var sink: (any PlayInputSink)?
        var triggerRole = TriggerRole.gameButtons
        var faceLayout = FaceLayout.positional
        var stick = StickDirectionResolver()
        var buttons: UInt32 = 0
        var joypad: UInt32 = 0
        var triggers: [UInt8] = [0, 0]
        var analog: [AnalogStick: [Int16]] = [:]
        var speed = PlaySpeed.normal
        var create = CreatePhase.idle
        var createTimer: UInt64 = 0
        var selectTap = false
        var selectTapTimer: UInt64 = 0

        mutating func publishJoypad() {
            let mask = buttons | (selectTap ? RetroPadButton.select.mask : 0)
            guard mask != joypad, let sink else { return }
            sink.setJoypad(mask)
            joypad = mask
        }

        mutating func publishTriggers(left: UInt8, right: UInt8) {
            guard [left, right] != triggers else { return }
            sink?.setTriggers(left: left, right: right)
            triggers = [left, right]
        }

        mutating func publishSpeed(_ speed: PlaySpeed) {
            guard speed != self.speed else { return }
            sink?.setSpeed(speed)
            self.speed = speed
        }

        mutating func settle() {
            publishSpeed(.normal)
            publishTriggers(left: 0, right: 0)
            if selectTap {
                selectTap = false
                selectTapTimer += 1
                publishJoypad()
            }
        }

        mutating func createChanged(down: Bool) -> PendingTimer? {
            switch (create, down) {
            case (.idle, true):
                create = .timing
                createTimer += 1
                return .captureHold(createTimer)
            case (.timing, false):
                create = .idle
                selectTap = true
                selectTapTimer += 1
                return .selectTap(selectTapTimer)
            case (.spent, false):
                create = .idle
                return nil
            case (.idle, false), (.timing, true), (.spent, true):
                return nil
            }
        }
    }

    // A Create hold of 500 ms opens capture; a shorter tap reaches the game as a 100 ms Select.
    private static let captureHold = DispatchTimeInterval.milliseconds(500)
    private static let selectTapLength = DispatchTimeInterval.milliseconds(100)

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let events: AsyncStream<RouterEvent>.Continuation
    private let queue: DispatchQueue

    init(events: AsyncStream<RouterEvent>.Continuation, queue: DispatchQueue) {
        self.events = events
        self.queue = queue
    }

    func setMode(_ mode: InputMode, leftStick: GCControllerDirectionPad?) {
        let magnitude = leftStick.map { max(abs($0.xAxis.value), abs($0.yAxis.value)) }
        state.withLock {
            if $0.mode != mode {
                $0.createTimer += 1
                if $0.create == .timing {
                    $0.create = .spent
                }
                $0.settle()
            }
            $0.mode = mode
            $0.stick.reset(magnitude: magnitude, at: .now)
        }
    }

    func setSink(_ sink: (any PlayInputSink)?) {
        state.withLock {
            $0.settle()
            $0.sink = sink
        }
    }

    func setTriggerRole(_ role: TriggerRole) {
        state.withLock { $0.triggerRole = role }
    }

    func setFaceLayout(_ layout: FaceLayout) {
        state.withLock { $0.faceLayout = layout }
    }

    func attach(_ gamepad: GCExtendedGamepad) {
        let stick = gamepad.leftThumbstick
        let magnitude = max(abs(stick.xAxis.value), abs(stick.yAxis.value))
        state.withLock { $0.stick.reset(magnitude: magnitude, at: .now) }
        gamepad.buttonOptions?.preferredSystemGestureState = .disabled
        gamepad.buttonMenu.preferredSystemGestureState = .disabled
        let directions: [(GCControllerButtonInput, Direction)] = [
            (gamepad.dpad.up, .up), (gamepad.dpad.down, .down), (gamepad.dpad.left, .left), (
                gamepad.dpad.right,
                .right
            ),
        ]
        for (button, direction) in directions {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.directionChanged(direction, pressed: pressed)
            }
        }
        let actions: [(GCControllerButtonInput, NavigationAction)] = [
            (gamepad.buttonA, .confirm), (gamepad.buttonB, .back), (gamepad.buttonMenu, .options),
            (gamepad.buttonY, .secondary),
            (gamepad.leftShoulder, .section(.left)), (gamepad.rightShoulder, .section(.right)),
        ]
        for (button, action) in actions {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    self?.navigate(action)
                }
            }
        }
        gamepad.touchpadClick?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed {
                self?.pause()
            }
        }
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.rewindHeld(pressed)
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.stickChanged(x: x, y: y)
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.tiltChanged(x: x, y: y)
        }
        gamepad.valueChangedHandler = { [weak self] pad, _ in
            self?.playInput(pad)
        }
    }

    func detach(_ gamepad: GCExtendedGamepad) {
        let buttons = [
            gamepad.dpad.up, gamepad.dpad.down, gamepad.dpad.left, gamepad.dpad.right,
            gamepad.buttonA, gamepad.buttonB, gamepad.buttonY, gamepad.buttonMenu,
            gamepad.leftShoulder, gamepad.rightShoulder,
            gamepad.leftTrigger,
        ]
        for button in buttons {
            button.pressedChangedHandler = nil
        }
        gamepad.touchpadClick?.pressedChangedHandler = nil
        gamepad.leftThumbstick.valueChangedHandler = nil
        gamepad.rightThumbstick.valueChangedHandler = nil
        gamepad.valueChangedHandler = nil
    }

    private func directionChanged(_ direction: Direction, pressed: Bool) {
        guard state.withLock({ $0.mode == .navigation }) else { return }
        events.yield(pressed ? .directionPressed(direction) : .directionReleased(direction))
    }

    private func navigate(_ action: NavigationAction) {
        guard state.withLock({ $0.mode == .navigation }) else { return }
        events.yield(.action(action))
    }

    private func pause() {
        events.yield(.action(.pause))
    }

    private func rewindHeld(_ held: Bool) {
        guard state.withLock({ $0.mode == .navigation }) else { return }
        events.yield(.playControl(.rewindHeld(held)))
    }

    private func stickChanged(x: Float, y: Float) {
        let transition = state.withLock { state -> StickDirectionResolver.Transition? in
            guard state.mode == .navigation else { return nil }
            return state.stick.update(x: x, y: y, at: .now)
        }
        guard let transition else { return }
        if let released = transition.released {
            events.yield(.directionReleased(released))
        }
        if let pressed = transition.pressed {
            events.yield(.directionPressed(pressed))
        }
    }

    private func tiltChanged(x: Float, y: Float) {
        guard state.withLock({ $0.mode == .navigation }) else { return }
        events.yield(.tilt(MenuTilt(x: Self.deadZoned(x), y: Self.deadZoned(y))))
    }

    private static func deadZoned(_ value: Float) -> Double {
        abs(value) < Motion.tiltDeadZone ? 0 : Double(value)
    }

    private struct StickValues {
        let stick: AnalogStick
        let x: Int16
        let y: Int16
    }

    private func playInput(_ gamepad: GCExtendedGamepad) {
        let pressed = Self.joypadMask(gamepad)
        let leftTrigger = Self.triggerByte(gamepad.leftTrigger)
        let rightTrigger = Self.triggerByte(gamepad.rightTrigger)
        let current = [
            Self.stickValues(.left, gamepad.leftThumbstick),
            Self.stickValues(.right, gamepad.rightThumbstick),
        ]
        let timer = state.withLock { state -> PendingTimer? in
            let createDown = pressed & RetroPadButton.select.mask != 0
            guard state.mode == .play, let sink = state.sink else {
                state.create = createDown ? .spent : .idle
                return nil
            }
            let timer = state.createChanged(down: createDown)
            var buttons = Self.laidOut(pressed & ~RetroPadButton.select.mask, state.faceLayout)
            switch state.triggerRole {
            case .speedControls:
                buttons &= ~(RetroPadButton.l2.mask | RetroPadButton.r2.mask)
                state.publishSpeed(Self.speed(
                    leftTrigger: pressed & RetroPadButton.l2.mask != 0,
                    rightTrigger: pressed & RetroPadButton.r2.mask != 0
                ))
            case .gameButtons:
                state.publishSpeed(.normal)
            }
            state.buttons = buttons
            state.publishJoypad()
            state.publishTriggers(left: leftTrigger, right: rightTrigger)
            for values in current where state.analog[values.stick] != [values.x, values.y] {
                state.analog[values.stick] = [values.x, values.y]
                sink.setAnalog(values.stick, x: values.x, y: values.y)
            }
            return timer
        }
        switch timer {
        case .captureHold(let id):
            queue.asyncAfter(deadline: .now() + Self.captureHold) { [weak self] in
                self?.captureHoldElapsed(id)
            }
        case .selectTap(let id):
            queue.asyncAfter(deadline: .now() + Self.selectTapLength) { [weak self] in
                self?.selectTapElapsed(id)
            }
        case nil:
            break
        }
    }

    private func captureHoldElapsed(_ id: UInt64) {
        let fired = state.withLock { state -> Bool in
            guard state.createTimer == id, state.create == .timing else { return false }
            state.create = .spent
            return true
        }
        if fired {
            events.yield(.playControl(.captureRequested))
        }
    }

    private func selectTapElapsed(_ id: UInt64) {
        state.withLock { state in
            guard state.selectTapTimer == id, state.selectTap else { return }
            state.selectTap = false
            state.publishJoypad()
        }
    }
}

extension ControllerInputRouter {
    private static func speed(leftTrigger: Bool, rightTrigger: Bool) -> PlaySpeed {
        if leftTrigger {
            .rewind
        } else if rightTrigger {
            .fastForward
        } else {
            .normal
        }
    }

    private static func triggerByte(_ trigger: GCControllerButtonInput) -> UInt8 {
        UInt8(clamping: Int((trigger.value * 255).rounded()))
    }

    private static func joypadMask(_ gamepad: GCExtendedGamepad) -> UInt32 {
        let mapping: [(GCControllerButtonInput?, RetroPadButton)] = [
            (gamepad.buttonA, .b), (gamepad.buttonB, .a), (gamepad.buttonX, .y), (gamepad.buttonY, .x),
            (gamepad.leftShoulder, .l), (gamepad.rightShoulder, .r),
            (gamepad.leftTrigger, .l2), (gamepad.rightTrigger, .r2),
            (gamepad.leftThumbstickButton, .l3), (gamepad.rightThumbstickButton, .r3),
            (gamepad.buttonOptions, .select), (gamepad.buttonMenu, .start),
            (gamepad.dpad.up, .up), (gamepad.dpad.down, .down), (gamepad.dpad.left, .left), (
                gamepad.dpad.right,
                .right
            ),
        ]
        return mapping.reduce(into: 0) { mask, entry in
            if entry.0?.isPressed == true {
                mask |= entry.1.mask
            }
        }
    }

    private static func laidOut(_ mask: UInt32, _ layout: FaceLayout) -> UInt32 {
        guard layout == .jumpOnCross else { return mask }
        let cross = RetroPadButton.b.mask, circle = RetroPadButton.a.mask, square = RetroPadButton.y.mask
        let jump = mask & cross != 0 ? RetroPadButton.a.mask : 0
        let run = mask & (circle | square) != 0 ? RetroPadButton.b.mask : 0
        return mask & ~(cross | circle | square) | jump | run
    }

    private static func stickValues(_ stick: AnalogStick, _ pad: GCControllerDirectionPad) -> StickValues {
        StickValues(stick: stick, x: scaled(pad.xAxis.value), y: scaled(-pad.yAxis.value))
    }

    private static func scaled(_ value: Float) -> Int16 {
        Int16(clamping: Int((value * 32768).rounded()))
    }
}

extension GCExtendedGamepad {
    var touchpadClick: GCControllerButtonInput? {
        switch self {
        case let dualSense as GCDualSenseGamepad: dualSense.touchpadButton
        case let dualShock as GCDualShockGamepad: dualShock.touchpadButton
        default: nil
        }
    }
}
