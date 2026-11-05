import Foundation

final class XboxFrames {
    static let aspectRatio = 4.0 / 3.0

    private let shm: UnsafeMutablePointer<CartridgeSharedMemory>
    private let tap: UnsafeMutablePointer<CartridgeAudioTap>?
    private let guestFrames: XemuLibrary.GuestFrames
    private let client: (any CoreHostClientProtocol)?
    private var width: UInt32
    private var height: UInt32
    private var countedGuestFrames: UInt64 = 0

    init(
        shm: UnsafeMutablePointer<CartridgeSharedMemory>,
        tap: UnsafeMutablePointer<CartridgeAudioTap>?,
        guestFrames: @escaping XemuLibrary.GuestFrames,
        client: (any CoreHostClientProtocol)?,
        width: UInt32,
        height: UInt32
    ) {
        self.shm = shm
        self.tap = tap
        self.guestFrames = guestFrames
        self.client = client
        self.width = width
        self.height = height
    }

    func publish(surface: UInt32, width: UInt32, height: UInt32) {
        guard surface < FrameSurfaceFormat.count else { return }
        cartridge_shm_publish_frame(shm, CartridgeFrame(
            surface: surface,
            width: width,
            height: height,
            pacingInterval: 0,
            startNs: clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        ))
        let guestTotal = guestFrames()
        if guestTotal > countedGuestFrames {
            cartridge_shm_add_frames_produced(shm, guestTotal - countedGuestFrames)
        }
        countedGuestFrames = guestTotal
        if let tap {
            cartridge_tap_tag(tap, cartridge_shm_read_frame(shm).sequence)
        }
        guard width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        client?.geometryDidChange(
            baseWidth: Int32(clamping: width),
            baseHeight: Int32(clamping: height),
            aspectRatio: Self.aspectRatio
        )
    }
}
