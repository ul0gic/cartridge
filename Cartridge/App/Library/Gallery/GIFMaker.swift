import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct GIFOutput: Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let frames: Int
    let durationSeconds: Double
}

private enum GIFRenderError: Error {
    case noVideo
    case badSize
    case noFrames
    case bitmapUnavailable
    case destinationUnavailable
    case finalizeFailed
}

enum GIFMaker {
    static let framesPerSecond = 20.0
    static let pixelHeight = 360
    private static let fallbackSourceRate = 60.0

    @concurrent
    static func write(clip: URL, to destination: URL) async throws(GalleryError) -> GIFOutput {
        do {
            return try await render(clip: clip, to: destination)
        } catch {
            GalleryLog.logger.error("gif failed: \(error.localizedDescription)")
            throw GalleryError.gifFailed
        }
    }

    private static func render(clip: URL, to destination: URL) async throws -> GIFOutput {
        let asset = AVURLAsset(url: clip)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GIFRenderError.noVideo
        }
        let naturalSize = try await track.load(.naturalSize)
        let nominalRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        guard naturalSize.width > 0, naturalSize.height > 0 else { throw GIFRenderError.badSize }

        let width = Int((naturalSize.width * Double(pixelHeight) / naturalSize.height).rounded())
        let interval = 1 / framesPerSecond
        let tolerance = 0.5 / (nominalRate > 0 ? Double(nominalRate) : fallbackSourceRate)
        let capacity = Int((duration * framesPerSecond).rounded(.up)) + 1

        let sink = try gifDestination(at: destination, capacity: capacity)
        let delay = [kCGImagePropertyGIFUnclampedDelayTime: interval]
        let frameProperties = [kCGImagePropertyGIFDictionary: delay] as CFDictionary

        let reader = try AVAssetReader(asset: asset)
        let settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        let provider = reader.outputProvider(for: output)
        try reader.start()

        var origin: Double?
        var emitted = 0
        while let ready = try await provider.next() {
            try ready.withUnsafeSampleBuffer { sample in
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let start = origin ?? time
                origin = start
                guard time >= start + Double(emitted) * interval - tolerance else { return }
                let frame = try scaled(pixels, width: width)
                while time >= start + Double(emitted) * interval - tolerance {
                    CGImageDestinationAddImage(sink, frame, frameProperties)
                    emitted += 1
                }
            }
        }
        guard emitted > 0 else { throw GIFRenderError.noFrames }
        guard CGImageDestinationFinalize(sink) else { throw GIFRenderError.finalizeFailed }
        return GIFOutput(
            pixelWidth: width,
            pixelHeight: pixelHeight,
            frames: emitted,
            durationSeconds: Double(emitted) * interval
        )
    }

    private static func gifDestination(at url: URL, capacity: Int) throws -> CGImageDestination {
        guard let sink = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, capacity, nil
        ) else { throw GIFRenderError.destinationUnavailable }
        let loop = [kCGImagePropertyGIFLoopCount: 0]
        CGImageDestinationSetProperties(sink, [kCGImagePropertyGIFDictionary: loop] as CFDictionary)
        return sink
    }

    private static func scaled(_ pixels: CVPixelBuffer, width: Int) throws -> CGImage {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let base = CVPixelBufferGetBaseAddress(pixels),
              let source = CGContext(
                  data: base,
                  width: CVPixelBufferGetWidth(pixels),
                  height: CVPixelBufferGetHeight(pixels),
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                  space: space,
                  bitmapInfo: bitmapInfo
              ),
              let sourceImage = source.makeImage(),
              let target = CGContext(
                  data: nil,
                  width: width,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: bitmapInfo
              )
        else { throw GIFRenderError.bitmapUnavailable }
        target.interpolationQuality = .high
        target.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: pixelHeight))
        guard let image = target.makeImage() else { throw GIFRenderError.bitmapUnavailable }
        return image
    }
}
