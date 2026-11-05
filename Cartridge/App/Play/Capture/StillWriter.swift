import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

enum StillWriter {
    static let pixelHeight = 2160

    static func makeBuffer(width: Int) -> CVReadOnlyPixelBuffer? {
        var attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: width, height: pixelHeight),
            compatibility: [.metalTexture]
        )
        attributes.backing = .ioSurface
        do {
            return try CVReadOnlyPixelBuffer(CVMutablePixelBuffer(attributes))
        } catch {
            PlayLog.session.error("capture-still-buffer-failed \(error.localizedDescription)")
            return nil
        }
    }

    @concurrent
    static func write(_ buffer: CVReadOnlyPixelBuffer, to destination: URL) async throws(CaptureError) {
        let work = try CaptureFiles.newPartialURL(pathExtension: CaptureKind.screenshot.fileExtension)
        guard buffer.withUnsafeBuffer({ writePNG(of: $0, to: work) }) else {
            PlayLog.session.error("capture-png-failed")
            CaptureFiles.remove(work)
            throw .encoderFailed
        }
        do {
            try CaptureFiles.move(work, to: destination)
        } catch {
            CaptureFiles.remove(work)
            throw error
        }
    }

    private static func writePNG(of pixelBuffer: CVPixelBuffer, to url: URL) -> Bool {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return false }
        let data = Data(bytes: base, count: bytesPerRow * height)
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
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
