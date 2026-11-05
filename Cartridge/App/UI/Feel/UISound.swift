import AVFoundation

@MainActor
enum UISound: String, CaseIterable {
    case intro
    case move
    case select
    case back
    case tab
    case insert
    case insertDisc

    private static var players: [UISound: AVAudioPlayer] = [:]
    private static let log = LogChannel(category: "sound")

    static func play(_ sound: UISound) {
        guard isEnabled(sound), let player = players[sound] ?? load(sound) else { return }
        player.currentTime = 0
        player.volume = baseVolume(sound)
        player.play()
    }

    static func fadeOut(_ sound: UISound) {
        guard let player = players[sound], player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.35)
    }

    static func isEnabled(_ sound: UISound) -> Bool {
        let key = sound == .intro ? DefaultsKey.introSound : DefaultsKey.interfaceSounds
        return UserDefaults.standard.object(forKey: key.rawValue) as? Bool ?? true
    }

    private static func baseVolume(_ sound: UISound) -> Float {
        sound == .intro ? 1 : 0.5
    }

    private static func load(_ sound: UISound) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "m4a") else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[sound] = player
            return player
        } catch {
            log
                .error(
                    "sound-load-failed name=\(sound.rawValue) \(error.localizedDescription)"
                )
            return nil
        }
    }
}
