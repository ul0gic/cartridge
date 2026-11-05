import Foundation

struct AudioBufferProfile {
    let primeMs: Double
    let ringMs: Double
    let targetMs: Double

    static func forCore(at path: String) -> AudioBufferProfile {
        switch (path as NSString).lastPathComponent {
        case "mupen64plus_next_libretro.dylib":
            AudioBufferProfile(primeMs: 200, ringMs: 300, targetMs: 140)
        default:
            AudioBufferProfile(primeMs: 100, ringMs: 200, targetMs: 100)
        }
    }

    func frames(_ milliseconds: Double, sampleRate: Double) -> UInt32 {
        UInt32(milliseconds * sampleRate / 1000)
    }
}
