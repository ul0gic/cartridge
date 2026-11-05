import Foundation

final class AudioTapWriter {
    private let tap: UnsafeMutablePointer<CartridgeAudioTap>

    init?(sharedMemoryName: String, sampleRate: Double) {
        guard let token = CartridgeSharedMemoryLayout.sessionToken(fromName: sharedMemoryName) else {
            CoreHostLog.session.error("tap-unavailable reason=unnamed")
            return nil
        }
        guard let tap = cartridge_tap_open(CartridgeSharedMemoryLayout.audioTapName(for: token)) else {
            CoreHostLog.session.error("tap-unavailable errno=\(errno)")
            return nil
        }
        self.tap = tap
        cartridge_tap_set_rate(tap, UInt32(sampleRate.rounded()))
    }

    func write(left: Int16, right: Int16) {
        withUnsafePointer(to: (left, right)) { frame in
            frame.withMemoryRebound(to: Int16.self, capacity: 2) { cartridge_tap_write(tap, $0, 1) }
        }
    }

    func write(frames: UnsafePointer<Int16>, count: Int) {
        cartridge_tap_write(tap, frames, count)
    }

    func tag(frameSequence: UInt64) {
        cartridge_tap_tag(tap, frameSequence)
    }

    func unmap() {
        cartridge_tap_unmap(tap)
    }
}
