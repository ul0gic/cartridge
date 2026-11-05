final class InputSnapshot {
    private static let deviceMask: UInt32 = (1 << UInt32(RETRO_DEVICE_TYPE_SHIFT)) - 1

    private let shm: UnsafeMutablePointer<CartridgeSharedMemory>
    private var state = CartridgeInputState()

    init(shm: UnsafeMutablePointer<CartridgeSharedMemory>) {
        self.shm = shm
    }

    func poll() {
        state = cartridge_shm_read_input(shm)
    }

    func value(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
        guard port == 0 else {
            return 0
        }
        switch device & Self.deviceMask {
        case UInt32(RETRO_DEVICE_JOYPAD):
            return joypad(id: id)
        case UInt32(RETRO_DEVICE_ANALOG):
            return analog(index: index, id: id)
        default:
            return 0
        }
    }

    private func joypad(id: UInt32) -> Int16 {
        if id == UInt32(RETRO_DEVICE_ID_JOYPAD_MASK) {
            return Int16(truncatingIfNeeded: state.joypad0)
        }
        guard id < 16 else {
            return 0
        }
        return state.joypad0 & (1 << id) == 0 ? 0 : 1
    }

    private func analog(index: UInt32, id: UInt32) -> Int16 {
        switch (index, id) {
        case (UInt32(RETRO_DEVICE_INDEX_ANALOG_LEFT), UInt32(RETRO_DEVICE_ID_ANALOG_X)):
            state.analogLeftX
        case (UInt32(RETRO_DEVICE_INDEX_ANALOG_LEFT), UInt32(RETRO_DEVICE_ID_ANALOG_Y)):
            state.analogLeftY
        case (UInt32(RETRO_DEVICE_INDEX_ANALOG_RIGHT), UInt32(RETRO_DEVICE_ID_ANALOG_X)):
            state.analogRightX
        case (UInt32(RETRO_DEVICE_INDEX_ANALOG_RIGHT), UInt32(RETRO_DEVICE_ID_ANALOG_Y)):
            state.analogRightY
        default:
            0
        }
    }
}
