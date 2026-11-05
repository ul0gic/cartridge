import Foundation

struct XboxAudio {
    static let sampleRate: UInt32 = 48000

    let shm: UnsafeMutablePointer<CartridgeSharedMemory>
    let tap: UnsafeMutablePointer<CartridgeAudioTap>?

    static func openTap(sharedMemoryName: String) -> UnsafeMutablePointer<CartridgeAudioTap>? {
        guard let token = CartridgeSharedMemoryLayout.sessionToken(fromName: sharedMemoryName) else {
            XboxHostLog.session.error("tap-unavailable reason=unnamed")
            return nil
        }
        guard let tap = cartridge_tap_open(CartridgeSharedMemoryLayout.audioTapName(for: token)) else {
            XboxHostLog.session.error("tap-unavailable errno=\(errno)")
            return nil
        }
        cartridge_tap_set_rate(tap, sampleRate)
        return tap
    }

    func write(_ frames: UnsafePointer<Int16>, count: UInt32) {
        guard let tap else { return }
        cartridge_tap_write(tap, frames, Int(count))
    }

    func underrun() {
        cartridge_shm_add_audio_underruns(shm, 1)
    }
}
