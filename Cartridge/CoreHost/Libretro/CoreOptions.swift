import Foundation

enum CoreOptions {
    static func table(forCoreAt path: String) -> [String: String] {
        switch (path as NSString).lastPathComponent {
        case "mupen64plus_next_libretro.dylib":
            [
                "mupen64plus-rdp-plugin": "angrylion",
                "mupen64plus-rsp-plugin": "cxd4",
                "mupen64plus-cpucore": "cached_interpreter",
                "mupen64plus-43screensize": "640x480",
                "mupen64plus-ThreadedRenderer": "False",
                "mupen64plus-pak1": "memory",
            ]
        case "mednafen_psx_libretro.dylib":
            [
                "beetle_psx_cpu_dynarec": "disabled",
                "beetle_psx_use_mednafen_memcard0_method": "libretro",
                "beetle_psx_shared_memory_cards": "disabled",
                // Off forces the DualShock into analog mode (frontio.c:1997); digital-only games ignore it.
                "beetle_psx_analog_toggle": "enabled",
            ]
        default:
            [:]
        }
    }
}
