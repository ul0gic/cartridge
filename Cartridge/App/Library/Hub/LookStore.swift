import Foundation

@MainActor
final class LookStore {
    private let defaults = UserDefaults.standard

    func look(for system: GameSystem) -> DisplayLook {
        defaults.string(forKey: Self.key(for: system)).flatMap(DisplayLook.init(rawValue:)) ?? .original
    }

    func setLook(_ look: DisplayLook, for system: GameSystem) {
        defaults.set(look.rawValue, forKey: Self.key(for: system))
    }

    private static func key(for system: GameSystem) -> String {
        "\(DefaultsKey.displayLook.rawValue).\(system.rawValue)"
    }
}
