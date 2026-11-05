import Foundation

struct RewindProfile {
    let captureEvery: Int
    let stepEvery: Int
    let budgetBytes: Int
    let fastSavestates: Bool

    /// Gate 0 table (build-plan Notes & Decisions, evidence/phase0/rewind/summary.md); N64 keeps no history.
    static func forCore(at path: String) -> RewindProfile? {
        switch (path as NSString).lastPathComponent {
        case "mesen_libretro.dylib", "genesis_plus_gx_libretro.dylib":
            RewindProfile(captureEvery: 1, stepEvery: 1, budgetBytes: 96 << 20, fastSavestates: false)
        case "snes9x_libretro.dylib":
            RewindProfile(captureEvery: 1, stepEvery: 1, budgetBytes: 96 << 20, fastSavestates: true)
        case "mednafen_psx_libretro.dylib":
            RewindProfile(captureEvery: 1, stepEvery: 1, budgetBytes: 160 << 20, fastSavestates: true)
        default:
            nil
        }
    }
}
