public enum RetroPadButton: UInt32 {
    // swiftlint:disable identifier_name - libretro's single-letter button ids, names fixed by contracts.md
    case b = 0
    case y = 1
    case select = 2
    case start = 3
    case up = 4
    case down = 5
    case left = 6
    case right = 7
    case a = 8
    case x = 9
    case l = 10
    case r = 11
    case l2 = 12
    case r2 = 13
    case l3 = 14
    case r3 = 15
    // swiftlint:enable identifier_name

    public var mask: UInt32 {
        1 << rawValue
    }
}

public enum LibretroControllerDevice: UInt32 {
    case joypad = 1
    case psDualShock = 517
}
