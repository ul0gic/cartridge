import CoreGraphics
import ImageIO
import IOSurface
import UniformTypeIdentifiers

struct FrameSurfaces {
    let surfaces: [IOSurface]

    init?(size: FrameSurfaceSize) {
        let created = (0..<FrameSurfaceFormat.count).compactMap { _ in
            IOSurface(properties: FrameSurfaceFormat.properties(for: size))
        }
        guard created.count == FrameSurfaceFormat.count else { return nil }
        surfaces = created
    }

    func writeSnapshot(of info: CartridgeFrameInfo, to url: URL) -> Bool {
        let index = Int(info.front)
        guard info.sequence > 0, surfaces.indices.contains(index), info.width > 0, info.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return false }
        let surface = surfaces[index]
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let width = min(Int(info.width), surface.width)
        let height = min(Int(info.height), surface.height)
        let data = Data(bytes: surface.baseAddress, count: surface.bytesPerRow * height)
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: surface.bytesPerRow,
                  space: space,
                  bitmapInfo: bitmap,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
