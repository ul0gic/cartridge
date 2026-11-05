import CoreHaptics
import GameController

@MainActor
final class ControllerFeel {
    private weak var controller: GCController?
    private var engine: CHHapticEngine?
    private var hasLoggedFailure = false
    private let log = LogChannel(category: "controller")

    func attach(_ controller: GCController?) {
        engine?.stop()
        engine = nil
        self.controller = controller
    }

    func play(_ kind: FeedbackKind) {
        guard let haptics = controller?.haptics else { return }
        do {
            let engine = try currentEngine(haptics)
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: kind == .confirm ? 0.8 : 0.35),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: kind == .confirm ? 0.5 : 0.8),
                ],
                relativeTime: 0
            )
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            guard !hasLoggedFailure else { return }
            hasLoggedFailure = true
            log.error("haptics-failed \(error.localizedDescription)")
        }
    }

    func setLight(red: Float, green: Float, blue: Float) {
        controller?.light?.color = GCColor(red: red, green: green, blue: blue)
    }

    private func currentEngine(_ haptics: GCDeviceHaptics) throws -> CHHapticEngine {
        if let engine {
            return engine
        }
        guard let created = haptics.createEngine(withLocality: .default) else {
            throw CocoaError(.featureUnsupported)
        }
        try created.start()
        engine = created
        return created
    }
}
