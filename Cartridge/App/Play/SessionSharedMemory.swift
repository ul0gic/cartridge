import Foundation

// @unchecked: the mapped pointer is immutable and every access goes through the atomic C accessors.
final class SessionSharedMemory: PlayInputSink, @unchecked Sendable {
    let name: String
    private let pointer: UnsafeMutablePointer<CartridgeSharedMemory>?

    var isMapped: Bool {
        pointer != nil
    }

    init(token: String) {
        name = CartridgeSharedMemoryLayout.name(for: token)
        pointer = cartridge_shm_create(name)
        if pointer == nil {
            PlayLog.session.error("shm-create-failed errno=\(errno)")
        }
    }

    deinit {
        unlink()
        if let pointer {
            cartridge_shm_unmap(pointer)
        }
    }

    func unlink() {
        guard pointer != nil else { return }
        if cartridge_shm_unlink(name) != 0, errno != ENOENT {
            PlayLog.session.error("shm-unlink-failed errno=\(errno)")
        }
    }

    func setJoypad(_ mask: UInt32) {
        guard let pointer else { return }
        cartridge_shm_write_joypad(pointer, mask)
    }

    func setAnalog(_ stick: AnalogStick, x: Int16, y: Int16) {
        guard let pointer else { return }
        cartridge_shm_write_analog(pointer, stick == .left ? 0 : 1, x, y)
    }

    func setTriggers(left: UInt8, right: UInt8) {
        guard let pointer else { return }
        cartridge_shm_write_triggers(pointer, left, right)
    }

    func setSpeed(_ speed: PlaySpeed) {
        guard let pointer else { return }
        cartridge_shm_write_speed_request(pointer, speed.rawValue)
    }

    func readActiveSpeed() -> ActiveSpeed? {
        pointer.flatMap { ActiveSpeed(rawValue: cartridge_shm_read_speed_active($0)) }
    }

    func setDisplay(tickNs: UInt64, periodNs: UInt64) {
        guard let pointer else { return }
        cartridge_shm_write_display(pointer, tickNs, periodNs)
    }

    func readFrame() -> CartridgeFrameInfo? {
        pointer.map { cartridge_shm_read_frame($0) }
    }

    func readFrames() -> CartridgeFrames? {
        pointer.map { cartridge_shm_read_frames($0) }
    }

    func readCounters() -> CartridgeCounters? {
        pointer.map { cartridge_shm_read_counters($0) }
    }

    func readCoreSchedule() -> CartridgeCoreSchedule? {
        pointer.map { cartridge_shm_read_core_schedule($0) }
    }
}
