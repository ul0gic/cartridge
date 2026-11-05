import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import SwiftUI

struct ArtColors: Sendable {
    let top: Color
    let middle: Color
    let bottom: Color
}

struct ArtEdgeColors: Sendable {
    let left: SIMD3<Double>
    let top: SIMD3<Double>
    let right: SIMD3<Double>
}

final class LoadedArt: Sendable, Equatable {
    let image: CGImage
    let colors: ArtColors

    init(image: CGImage, colors: ArtColors) {
        self.image = image
        self.colors = colors
    }

    static func == (lhs: LoadedArt, rhs: LoadedArt) -> Bool {
        lhs === rhs
    }
}

enum TileArt: Equatable {
    case loading
    case placeholder
    case image(LoadedArt)
}

enum ArtDecoder {
    nonisolated(unsafe) private static let cache = NSCache<NSURL, LoadedArt>() // NSCache is thread-safe, not Sendable

    @concurrent
    static func load(_ url: URL) async -> LoadedArt? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let loaded = await decode(url) else { return nil }
        cache.setObject(loaded, forKey: url as NSURL)
        return loaded
    }

    @concurrent
    static func decode(_ url: URL) async -> LoadedArt? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colors = thirds(of: image)
        else { return nil }
        return LoadedArt(image: image, colors: colors)
    }

    @concurrent
    static func edgeColors(of image: CGImage) async -> ArtEdgeColors? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let context = CIContext()
        let strip = extent.width * 0.06
        let band = extent.height * 0.04
        guard let left = average(of: source, in: extent.divided(atDistance: strip, from: .minXEdge).slice, context),
              let top = average(of: source, in: extent.divided(atDistance: band, from: .maxYEdge).slice, context),
              let right = average(of: source, in: extent.divided(atDistance: strip, from: .maxXEdge).slice, context)
        else { return nil }
        return ArtEdgeColors(left: left, top: top, right: right)
    }

    private static func thirds(of image: CGImage) -> ArtColors? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let band = extent.height / 3
        let context = CIContext()
        let averages = (0..<3).compactMap { index -> Color? in
            let area = CGRect(x: extent.minX, y: extent.minY + band * CGFloat(index), width: extent.width, height: band)
            return average(of: source, in: area, context).map { Color(.sRGB, red: $0.x, green: $0.y, blue: $0.z) }
        }
        guard averages.count == 3 else { return nil }
        return ArtColors(top: averages[2], middle: averages[1], bottom: averages[0])
    }

    private static func average(of source: CIImage, in area: CGRect, _ context: CIContext) -> SIMD3<Double>? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = source
        filter.extent = area
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2])) / 255
    }
}
