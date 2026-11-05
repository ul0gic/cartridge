import AVFoundation
import Foundation

struct AudioLevel {
    let measuredRate: UInt32
    let fillMs: UInt64
}

final class AudioOutput {
    private static let supportedSampleRates: ClosedRange<Double> = 8000...384_000

    private static let logIntervalNs: UInt64 = 10_000_000_000

    private let ring: UnsafeMutablePointer<CartridgeAudioRing>
    private let engine = AVAudioEngine()
    private let nominalRate: UInt32
    private var running = false
    private var lastTickNs: UInt64 = 0
    private var unpausedNs: UInt64 = 0
    private var loggedRejectedWindows: UInt32 = 0

    init(
        sampleRate: Double,
        profile: AudioBufferProfile,
        shm: UnsafeMutablePointer<CartridgeSharedMemory>
    ) throws(CoreHostFailure) {
        guard Self.supportedSampleRates.contains(sampleRate),
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 2,
                  interleaved: false
              )
        else {
            throw CoreHostFailure(code: .audioUnavailable, message: "unsupported audio sample rate \(sampleRate)")
        }
        let nominalRate = UInt32(sampleRate.rounded())
        guard let ring = cartridge_audio_ring_create(
            nominalRate,
            profile.frames(profile.primeMs, sampleRate: sampleRate),
            profile.frames(profile.ringMs, sampleRate: sampleRate),
            profile.frames(profile.targetMs, sampleRate: sampleRate)
        ) else {
            throw CoreHostFailure(code: .audioUnavailable, message: "audio ring allocation failed")
        }
        self.ring = ring
        self.nominalRate = nominalRate

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else {
                return noErr
            }
            cartridge_audio_pull(ring, shm, left, right, frameCount)
            return noErr
        }
        engine.attach(node)
        do {
            try engine.connectNode(node, to: engine.mainMixerNode, format: format)
        } catch {
            throw CoreHostFailure(
                code: .audioUnavailable,
                message: "audio engine connect: \(error.localizedDescription)"
            )
        }
        engine.prepare()
    }

    deinit {
        engine.stop()
        cartridge_audio_ring_destroy(ring)
    }

    func start(atNs ns: UInt64) throws(CoreHostFailure) {
        do {
            try engine.start()
        } catch {
            throw CoreHostFailure(code: .audioUnavailable, message: "audio engine start: \(error.localizedDescription)")
        }
        resumeLogging(atNs: ns)
    }

    func stop() {
        running = false
        engine.stop()
    }

    func write(left: Int16, right: Int16) {
        withUnsafePointer(to: (left, right)) { frame in
            frame.withMemoryRebound(to: Int16.self, capacity: 2) { cartridge_audio_write(ring, $0, 1) }
        }
    }

    func write(frames: UnsafePointer<Int16>, count: Int) {
        cartridge_audio_write(ring, frames, UInt32(clamping: count))
    }

    var level: AudioLevel {
        AudioLevel(
            measuredRate: cartridge_audio_rate(ring),
            fillMs: UInt64(cartridge_audio_fill(ring)) * 1000 / UInt64(nominalRate)
        )
    }

    func setPaused(_ paused: Bool, atNs ns: UInt64) {
        cartridge_audio_set_paused(ring, paused ? 1 : 0)
        if paused {
            running = false
        } else {
            resumeLogging(atNs: ns)
        }
    }

    func tick(atNs ns: UInt64) {
        guard running else {
            return
        }
        unpausedNs += ns - lastTickNs
        lastTickNs = ns
        let rejectedWindows = cartridge_audio_rejected_windows(ring)
        if rejectedWindows != loggedRejectedWindows {
            loggedRejectedWindows = rejectedWindows
            CoreHostLog.session.notice(
                """
                audio-window-rejected count=\(rejectedWindows) window-rate=\(cartridge_audio_rejected_rate(ring)) \
                nominal=\(nominalRate) fill-ms=\(level.fillMs)
                """
            )
        }
        if unpausedNs >= Self.logIntervalNs {
            unpausedNs -= Self.logIntervalNs
            let level = level
            CoreHostLog.session.notice(
                "audio-rate measured=\(level.measuredRate) nominal=\(nominalRate) fill-ms=\(level.fillMs)"
            )
        }
    }

    private func resumeLogging(atNs ns: UInt64) {
        running = true
        lastTickNs = ns
    }
}
