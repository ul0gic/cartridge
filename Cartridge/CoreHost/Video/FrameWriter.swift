import Foundation
import IOSurface

enum PixelFormat {
    case xrgb8888
    case rgb565
    case zeroRGB1555

    init?(_ format: retro_pixel_format) {
        switch format {
        case RETRO_PIXEL_FORMAT_XRGB8888:
            self = .xrgb8888
        case RETRO_PIXEL_FORMAT_RGB565:
            self = .rgb565
        case RETRO_PIXEL_FORMAT_0RGB1555:
            self = .zeroRGB1555
        default:
            return nil
        }
    }
}

final class FrameWriter {
    let width: Int
    let height: Int
    private let surfaces: [IOSurface]
    private let shm: UnsafeMutablePointer<CartridgeSharedMemory>
    private var back = 0
    private var startNs: UInt64 = 0
    private var pacingInterval: UInt32 = 0
    private var clampLogged = false
    private var lockFailureLogged = false
    private(set) var publishedSequence: UInt64?

    init(surfaces: [IOSurface], shm: UnsafeMutablePointer<CartridgeSharedMemory>) throws(CoreHostFailure) {
        guard surfaces.count == FrameSurfaceFormat.count else {
            throw CoreHostFailure(code: .surfacesUnavailable, message: "expected \(FrameSurfaceFormat.count) surfaces")
        }
        for surface in surfaces {
            guard surface.pixelFormat == FrameSurfaceFormat.pixelFormat,
                  surface.bytesPerRow >= surface.width * FrameSurfaceFormat.bytesPerElement
            else {
                throw CoreHostFailure(code: .surfacesUnavailable, message: "surface is not BGRA8")
            }
        }
        self.surfaces = surfaces
        self.shm = shm
        width = min(surfaces[0].width, surfaces[1].width)
        height = min(surfaces[0].height, surfaces[1].height)
    }

    func beginFrame(startNs: UInt64, pacingInterval: UInt32) {
        self.startNs = startNs
        self.pacingInterval = pacingInterval
        publishedSequence = nil
    }

    func write(
        _ data: UnsafeRawPointer?,
        width sourceWidth: UInt32,
        height sourceHeight: UInt32,
        pitch: Int,
        format: PixelFormat
    ) {
        defer { cartridge_shm_add_frames_produced(shm, 1) }
        guard let data, sourceWidth > 0, sourceHeight > 0 else {
            return
        }
        let columns = min(Int(sourceWidth), width)
        let rows = min(Int(sourceHeight), height)
        if (columns < Int(sourceWidth) || rows < Int(sourceHeight)) && !clampLogged {
            clampLogged = true
            CoreHostLog.session.notice("frame-clamped w=\(sourceWidth) h=\(sourceHeight)")
        }
        let surface = surfaces[back]
        guard IOSurfaceLock(surface, [], nil) == KERN_SUCCESS else {
            if !lockFailureLogged {
                lockFailureLogged = true
                CoreHostLog.session.error("surface lock failed, frames dropped")
            }
            return
        }
        let destination = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
        let destinationPitch = IOSurfaceGetBytesPerRow(surface)
        let source = data.assumingMemoryBound(to: UInt8.self)
        let convert = switch format {
        case .xrgb8888: cartridge_convert_xrgb8888
        case .rgb565: cartridge_convert_rgb565
        case .zeroRGB1555: cartridge_convert_0rgb1555
        }
        convert(destination, destinationPitch, source, pitch, UInt32(columns), UInt32(rows))
        IOSurfaceUnlock(surface, [], nil)
        cartridge_shm_publish_frame(shm, CartridgeFrame(
            surface: UInt32(back),
            width: UInt32(columns),
            height: UInt32(rows),
            pacingInterval: pacingInterval,
            startNs: startNs
        ))
        publishedSequence = cartridge_shm_read_frame(shm).sequence
        back ^= 1
    }
}
