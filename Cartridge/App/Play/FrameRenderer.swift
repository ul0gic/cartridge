import AppKit
import IOSurface
import Metal
import QuartzCore

private struct Viewport: Equatable {
    let width: Int
    let height: Int
    let aspect: Double
}

private struct LookUniforms {
    // Layout mirrors LookUniforms in Looks.metal.
    var sourceSize: SIMD2<Float>
    var textureSize: SIMD2<Float>
    var outputSize: SIMD2<Float>
}

@MainActor
final class FrameRenderer: NSObject {
    var aspectRatio: Double?
    var needsRedraw = true
    var look = DisplayLook.original {
        didSet {
            needsRedraw = true
            lookChangedAt = .now
        }
    }

    weak var captureSink: (any CaptureFrameSink)?

    private let layer: CAMetalLayer
    private let queue: any MTLCommandQueue
    private let device: any MTLDevice
    private let originalPipeline: any MTLRenderPipelineState
    private let sharpPipeline: any MTLRenderPipelineState
    private let crtPipeline: any MTLRenderPipelineState
    private let surfaces: [IOSurface]
    private let memory: SessionSharedMemory
    private let stats: StatsLogger
    private var textures: [Int: any MTLTexture] = [:]
    private var link: CADisplayLink?
    private var lastSequence: UInt64 = 0
    private var shownFrame: CartridgeFrame?
    private var loggedViewport: Viewport?
    private var lookChangedAt: ContinuousClock.Instant?

    init?(layer: CAMetalLayer, surfaces: [IOSurface], memory: SessionSharedMemory, stats: StatsLogger) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { return nil }
        guard let originalPipeline = Self.makePipeline(device, library, fragment: "frameFragment", layer.pixelFormat),
              let sharpPipeline = Self.makePipeline(device, library, fragment: "sharpFragment", layer.pixelFormat),
              let crtPipeline = Self.makePipeline(device, library, fragment: "crtFragment", layer.pixelFormat)
        else { return nil }
        layer.device = device
        self.device = device
        self.originalPipeline = originalPipeline
        self.sharpPipeline = sharpPipeline
        self.crtPipeline = crtPipeline
        self.layer = layer
        self.queue = queue
        self.surfaces = surfaces
        self.memory = memory
        self.stats = stats
        super.init()
    }

    private static func makePipeline(
        _ device: any MTLDevice,
        _ library: any MTLLibrary,
        fragment: String,
        _ pixelFormat: MTLPixelFormat
    ) -> (any MTLRenderPipelineState)? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "frameVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            PlayLog.session.error("render-pipeline-failed \(fragment) \(error.localizedDescription)")
            return nil
        }
    }

    private func pipeline(for look: DisplayLook) -> any MTLRenderPipelineState {
        switch look {
        case .original: originalPipeline
        case .sharp: sharpPipeline
        case .crt: crtPipeline
        }
    }

    func start(in view: NSView) {
        guard link == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        needsRedraw = true
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private static func nanoseconds(_ seconds: CFTimeInterval) -> UInt64 {
        UInt64((seconds * 1_000_000_000).rounded())
    }

    @objc
    private func tick(_ link: CADisplayLink) {
        let tickNs = Self.nanoseconds(link.timestamp)
        let targetNs = max(Self.nanoseconds(link.targetTimestamp), tickNs)
        let refreshNs = targetNs - tickNs
        memory.setDisplay(tickNs: tickNs, periodNs: refreshNs)
        present(tickNs: tickNs, displayNs: targetNs, refreshNs: refreshNs)
        stats.sampleIfDue()
    }

    private func present(tickNs: UInt64, displayNs: UInt64, refreshNs: UInt64) {
        guard let aspectRatio, let frames = memory.readFrames(), frames.sequence > 0 else { return }
        let next = nextFrame(in: frames, tickNs: tickNs, refreshNs: refreshNs)
        defer { drawStill(aspectRatio: aspectRatio) }
        let presented = next.map {
            PresentedFrame(sequence: $0.sequence, displayNs: displayNs, aspectRatio: aspectRatio)
        }
        guard let frame = next?.frame ?? (needsRedraw ? shownFrame : nil),
              draw(frame, aspectRatio: aspectRatio, presented: presented)
        else { return }
        needsRedraw = false
        if let next {
            lastSequence = next.sequence
            shownFrame = next.frame
            stats.didPresent(next.frame, displayNs: displayNs, refreshNs: refreshNs)
        }
    }

    private func nextFrame(
        in frames: CartridgeFrames,
        tickNs: UInt64,
        refreshNs: UInt64
    ) -> (sequence: UInt64, frame: CartridgeFrame)? {
        if Self.isDue(frames.latest, tickNs: tickNs, refreshNs: refreshNs) {
            return frames.sequence == lastSequence ? nil : (frames.sequence, frames.latest)
        }
        let previousSequence = frames.sequence - 1
        guard previousSequence > lastSequence, Self.isDue(frames.previous, tickNs: tickNs, refreshNs: refreshNs)
        else { return nil }
        return (previousSequence, frames.previous)
    }

    private static func isDue(_ frame: CartridgeFrame, tickNs: UInt64, refreshNs: UInt64) -> Bool {
        guard frame.pacingInterval > 0 else { return true }
        // Due at the tick nearest n refreshes after its start; it then shows at that tick's targetTimestamp.
        return frame.startNs + UInt64(frame.pacingInterval) * refreshNs <= tickNs + refreshNs / 2
    }

    private func draw(_ frame: CartridgeFrame, aspectRatio: Double, presented: PresentedFrame?) -> Bool {
        guard let texture = texture(for: Int(frame.surface)),
              let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer()
        else { return false }

        let drawableWidth = Double(drawable.texture.width)
        let drawableHeight = Double(drawable.texture.height)
        let width = min(drawableWidth, drawableHeight * aspectRatio)
        let height = width / aspectRatio
        let viewport = MTLViewport(
            originX: (drawableWidth - width) / 2,
            originY: (drawableHeight - height) / 2,
            width: width,
            height: height,
            znear: 0,
            zfar: 1
        )
        guard encode(frame, texture, into: drawable.texture, viewport: viewport, buffer: buffer) else { return false }
        logViewport(width: width, height: height, aspectRatio: aspectRatio)
        buffer.present(drawable)
        buffer.commit()
        if let lookChangedAt {
            self.lookChangedAt = nil
            PlayLog.session.info(
                "look-drawn look=\(look.rawValue) ms=\(PlaySession.milliseconds(since: lookChangedAt))"
            )
        }
        if let presented, let target = captureSink?.videoTarget(for: presented, device: device) {
            capture(frame, texture, to: target)
        }
        return true
    }

    private func drawStill(aspectRatio: Double) {
        guard let shownFrame,
              let target = captureSink?.stillTarget(device: device, aspectRatio: aspectRatio)
        else { return }
        guard let texture = texture(for: Int(shownFrame.surface)) else {
            target.complete(false)
            return
        }
        capture(shownFrame, texture, to: target)
    }

    private func capture(_ frame: CartridgeFrame, _ texture: any MTLTexture, to target: CaptureTarget) {
        let complete = target.complete
        let output = target.texture
        guard output.pixelFormat == layer.pixelFormat, let buffer = queue.makeCommandBuffer() else {
            complete(false)
            return
        }
        let viewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(output.width),
            height: Double(output.height),
            znear: 0,
            zfar: 1
        )
        guard encode(frame, texture, into: output, viewport: viewport, buffer: buffer) else {
            complete(false)
            return
        }
        buffer.addCompletedHandler { complete($0.error == nil) }
        buffer.commit()
    }

    private func encode(
        _ frame: CartridgeFrame,
        _ texture: any MTLTexture,
        into target: any MTLTexture,
        viewport: MTLViewport,
        buffer: any MTLCommandBuffer
    ) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }

        encoder.setViewport(viewport)
        let source = SIMD2(
            Float(min(Int(frame.width), texture.width)),
            Float(min(Int(frame.height), texture.height))
        )
        let textureSize = SIMD2(Float(texture.width), Float(texture.height))
        var uvScale = source / textureSize
        var uniforms = LookUniforms(
            sourceSize: source,
            textureSize: textureSize,
            outputSize: SIMD2(Float(viewport.width), Float(viewport.height))
        )
        encoder.setRenderPipelineState(pipeline(for: look))
        encoder.setVertexBytes(&uvScale, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LookUniforms>.size, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func logViewport(width: Double, height: Double, aspectRatio: Double) {
        let viewport = Viewport(width: Int(width.rounded()), height: Int(height.rounded()), aspect: aspectRatio)
        guard viewport != loggedViewport else { return }
        loggedViewport = viewport
        PlayLog.session.info(
            "viewport w=\(viewport.width) h=\(viewport.height) aspect=\(String(format: "%.4f", aspectRatio))"
        )
    }

    private func texture(for index: Int) -> (any MTLTexture)? {
        if let cached = textures[index] {
            return cached
        }
        guard surfaces.indices.contains(index) else {
            PlayLog.session.error("frame-surface-out-of-range index=\(index)")
            return nil
        }
        let surface = surfaces[index]
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: surface.width,
            height: surface.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = layer.device?.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            PlayLog.session.error("frame-texture-failed index=\(index)")
            return nil
        }
        textures[index] = texture
        return texture
    }
}
