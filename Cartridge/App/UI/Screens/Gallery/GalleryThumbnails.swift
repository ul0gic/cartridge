import AVFoundation
import Foundation
import ImageIO

final class GalleryThumbnail: Sendable {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }
}

enum GalleryThumbnails {
    private static let maxPixelSize = 576

    nonisolated(unsafe) private static let cache = NSCache<NSURL, GalleryThumbnail>() // thread-safe, not Sendable

    static func cached(_ url: URL) -> GalleryThumbnail? {
        cache.object(forKey: url as NSURL)
    }

    @concurrent
    static func load(_ url: URL, kind: CaptureKind) async -> GalleryThumbnail? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = await decode(url, kind: kind) else { return nil }
        let thumbnail = GalleryThumbnail(image: image)
        cache.setObject(thumbnail, forKey: url as NSURL)
        return thumbnail
    }

    private static func decode(_ url: URL, kind: CaptureKind) async -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        switch kind {
        case .screenshot, .gif:
            return stillImage(at: url)
        case .clip:
            return await firstFrame(of: url)
        }
    }

    private static func stillImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func firstFrame(of url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        do {
            return try await generator.image(at: .zero).image
        } catch {
            GalleryLog.logger.error("clip thumbnail failed: \(error.localizedDescription)")
            return nil
        }
    }
}
