import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class GameFrameNSView: NSView {
    private let metalLayer = CAMetalLayer()
    private let renderer: FrameRenderer?

    init(surfaces: FrameSurfaces, memory: SessionSharedMemory, stats: StatsLogger) {
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.displaySyncEnabled = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        renderer = FrameRenderer(layer: metalLayer, surfaces: surfaces.surfaces, memory: memory, stats: stats)
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func makeBackingLayer() -> CALayer {
        metalLayer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            renderer?.stop()
        } else {
            updateDrawableSize()
            renderer?.start(in: self)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    func update(aspectRatio: Double?, look: DisplayLook, captureSink: (any CaptureFrameSink)?) {
        guard let renderer else { return }
        renderer.captureSink = captureSink
        if renderer.look != look {
            renderer.look = look
        }
        guard renderer.aspectRatio != aspectRatio else { return }
        renderer.aspectRatio = aspectRatio
        renderer.needsRedraw = true
    }

    func stop() {
        renderer?.stop()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 1
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        renderer?.needsRedraw = true
    }
}

struct GameFrameView: NSViewRepresentable {
    let surfaces: FrameSurfaces
    let memory: SessionSharedMemory
    let stats: StatsLogger
    let geometry: FrameGeometry?
    let look: DisplayLook
    let captureSink: (any CaptureFrameSink)?

    func makeNSView(context: Context) -> GameFrameNSView {
        let view = GameFrameNSView(surfaces: surfaces, memory: memory, stats: stats)
        view.update(aspectRatio: geometry?.aspectRatio, look: look, captureSink: captureSink)
        return view
    }

    func updateNSView(_ view: GameFrameNSView, context: Context) {
        view.update(aspectRatio: geometry?.aspectRatio, look: look, captureSink: captureSink)
    }

    static func dismantleNSView(_ view: GameFrameNSView, coordinator: ()) {
        view.stop()
    }
}
