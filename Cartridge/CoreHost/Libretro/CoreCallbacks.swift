private func environmentTrampoline(_ command: UInt32, _ data: UnsafeMutableRawPointer?) -> Bool {
    CoreCallbacks.current?.environment.handle(command, data) ?? false
}

private func videoTrampoline(_ data: UnsafeRawPointer?, _ width: UInt32, _ height: UInt32, _ pitch: Int) {
    guard let callbacks = CoreCallbacks.current else {
        return
    }
    callbacks.frameWriter.write(
        data,
        width: width,
        height: height,
        pitch: pitch,
        format: callbacks.environment.pixelFormat
    )
}

private func audioSampleTrampoline(_ left: Int16, _ right: Int16) {
    guard let callbacks = CoreCallbacks.current, callbacks.keepsSamples else {
        return
    }
    callbacks.audio?.write(left: left, right: right)
    callbacks.tap?.write(left: left, right: right)
}

private func audioBatchTrampoline(_ frames: UnsafePointer<Int16>?, _ count: Int) -> Int {
    guard let frames, let callbacks = CoreCallbacks.current, callbacks.keepsSamples else {
        return count
    }
    callbacks.audio?.write(frames: frames, count: count)
    callbacks.tap?.write(frames: frames, count: count)
    return count
}

private func inputPollTrampoline() {
    CoreCallbacks.current?.input.poll()
}

private func inputStateTrampoline(_ port: UInt32, _ device: UInt32, _ index: UInt32, _ id: UInt32) -> Int16 {
    CoreCallbacks.current?.input.value(port: port, device: device, index: index, id: id) ?? 0
}

final class CoreCallbacks {
    nonisolated(unsafe) static var current: CoreCallbacks?

    let environment: Environment
    let frameWriter: FrameWriter
    let input: InputSnapshot
    var audio: AudioOutput?
    var tap: AudioTapWriter?
    var keepsSamples = true

    init(environment: Environment, frameWriter: FrameWriter, input: InputSnapshot) {
        self.environment = environment
        self.frameWriter = frameWriter
        self.input = input
    }

    func installEnvironment(on library: CoreLibrary) {
        // libretro callbacks carry no user data; one core per process makes a process-wide slot sound.
        Self.current = self
        library.setEnvironment(environmentTrampoline)
    }

    func installRemaining(on library: CoreLibrary) {
        library.setCallbacks(
            video: videoTrampoline,
            audioSample: audioSampleTrampoline,
            audioSampleBatch: audioBatchTrampoline,
            inputPoll: inputPollTrampoline,
            inputState: inputStateTrampoline
        )
    }

    func remove() {
        Self.current = nil
    }
}
