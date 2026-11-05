struct XboxPad {
    private static let full: UInt8 = 255
    private static let buttonBits: [(RetroPadButton, Int32)] = [
        (.up, CARTRIDGE_XEMU_PAD_DPAD_UP),
        (.down, CARTRIDGE_XEMU_PAD_DPAD_DOWN),
        (.left, CARTRIDGE_XEMU_PAD_DPAD_LEFT),
        (.right, CARTRIDGE_XEMU_PAD_DPAD_RIGHT),
        (.start, CARTRIDGE_XEMU_PAD_START),
        (.select, CARTRIDGE_XEMU_PAD_BACK),
        (.l3, CARTRIDGE_XEMU_PAD_LEFT_THUMB),
        (.r3, CARTRIDGE_XEMU_PAD_RIGHT_THUMB),
    ]

    let shm: UnsafeMutablePointer<CartridgeSharedMemory>

    func read(into pad: UnsafeMutablePointer<CartridgeXemuPad>) {
        pad.pointee = Self.pad(from: cartridge_shm_read_input(shm))
    }

    private static func pad(from input: CartridgeInputState) -> CartridgeXemuPad {
        let mask = input.joypad0
        var pad = CartridgeXemuPad()
        pad.buttons = buttonBits.reduce(0) { bits, entry in
            mask & entry.0.mask != 0 ? bits | UInt16(entry.1) : bits
        }
        pad.a = analog(mask, .b)
        pad.b = analog(mask, .a)
        pad.x = analog(mask, .y)
        pad.y = analog(mask, .x)
        pad.white = analog(mask, .l)
        pad.black = analog(mask, .r)
        pad.left_trigger = input.leftTrigger
        pad.right_trigger = input.rightTrigger
        pad.left_x = input.analogLeftX
        pad.left_y = upPositive(input.analogLeftY)
        pad.right_x = input.analogRightX
        pad.right_y = upPositive(input.analogRightY)
        return pad
    }

    private static func analog(_ mask: UInt32, _ button: RetroPadButton) -> UInt8 {
        mask & button.mask != 0 ? full : 0
    }

    private static func upPositive(_ downPositive: Int16) -> Int16 {
        downPositive == .min ? .max : -downPositive
    }
}
