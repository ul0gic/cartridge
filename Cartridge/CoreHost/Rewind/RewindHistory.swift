import Foundation

enum RewindStep {
    case stepped
    case between
    case oldest
}

final class RewindHistory {
    private static let captureSampleCapacity = 4096
    private static let dropEvery = 2

    private let library: CoreLibrary
    private let environment: Environment
    private let profile: RewindProfile
    private let stateSize: Int
    private let ring: DeltaRing
    private var isOn = true
    private var failureLogged = false
    private var captureTick = 0
    private var stepTick = 0
    private var dropTick = 0
    private var captureUs: [UInt32] = []

    init?(library: CoreLibrary, environment: Environment, profile: RewindProfile) {
        environment.requestsFastSavestates = profile.fastSavestates
        let size = library.serializeSize()
        environment.requestsFastSavestates = false
        guard size > 0 else {
            CoreHostLog.session.notice("rewind-unavailable reason=size-zero")
            return nil
        }
        guard let ring = DeltaRing(stateSize: size, budgetBytes: profile.budgetBytes) else {
            CoreHostLog.session.notice("rewind-unavailable reason=size-too-large bytes=\(size)")
            return nil
        }
        self.library = library
        self.environment = environment
        self.profile = profile
        self.ring = ring
        stateSize = size
        captureUs.reserveCapacity(Self.captureSampleCapacity)
    }

    func capture() {
        guard isOn else { return }
        let due = captureTick == 0
        captureTick = (captureTick + 1) % profile.captureEvery
        guard due else { return }
        let startNs = FramePacing.nowNs()
        environment.requestsFastSavestates = profile.fastSavestates
        defer { environment.requestsFastSavestates = false }
        guard library.serializeSize() == stateSize else {
            turnOff(reason: "size-changed")
            return
        }
        guard library.serialize(into: ring.captureTarget(), size: stateSize) else {
            logFailure("retro_serialize")
            return
        }
        ring.commitCapture()
        if captureUs.count < Self.captureSampleCapacity {
            captureUs.append(UInt32(clamping: (FramePacing.nowNs() - startNs) / 1000))
        }
    }

    func stepBack() -> RewindStep {
        guard isOn else { return .oldest }
        let due = stepTick == 0
        stepTick = (stepTick + 1) % profile.stepEvery
        guard due else { return .between }
        dropTick = (dropTick + 1) % Self.dropEvery
        let dropped = dropTick == 0 ? ring.pop() : nil
        guard let state = ring.pop() ?? dropped else { return .oldest }
        environment.requestsFastSavestates = profile.fastSavestates
        defer { environment.requestsFastSavestates = false }
        guard library.unserialize(from: state, size: stateSize) else {
            logFailure("retro_unserialize")
            return .oldest
        }
        return .stepped
    }

    func rewindDidStart() {
        stepTick = 0
        dropTick = 0
    }

    func rewindDidEnd() {
        captureTick = 0
    }

    func clear() {
        ring.clear()
        captureTick = 0
    }

    func logHistory(periodNs: UInt64) {
        guard isOn else { return }
        let depthMs = UInt64(ring.entries * profile.captureEvery) * periodNs / 1_000_000
        CoreHostLog.session.notice("rewind-history frames=\(ring.entries) bytes=\(ring.usedBytes) depth-ms=\(depthMs)")
    }

    func logCaptureTiming() {
        guard !captureUs.isEmpty else { return }
        captureUs.sort()
        let last = captureUs.count - 1
        CoreHostLog.session.notice(
            "rewind-capture-us p50=\(captureUs[last / 2]) p95=\(captureUs[last * 95 / 100]) max=\(captureUs[last])"
        )
        captureUs.removeAll(keepingCapacity: true)
    }

    private func turnOff(reason: String) {
        isOn = false
        ring.clear()
        CoreHostLog.session.notice("rewind-unavailable reason=\(reason)")
    }

    private func logFailure(_ call: String) {
        guard !failureLogged else { return }
        failureLogged = true
        CoreHostLog.session.error("rewind-\(call)-failed")
    }
}

/// RetroArch's reverse-delta ring (state_manager.c:481-760): each record is a forward link, a patch that turns
/// the newer state into the older one, and a back link; the newest full state lives in `thisBlock`.
private final class DeltaRing {
    private static let linkBytes = MemoryLayout<Int>.size

    private let blockSize: Int
    private let maxRecordBytes: Int
    private let capacity: Int
    private let data: UnsafeMutableRawPointer
    private var thisBlock: UnsafeMutableRawPointer
    private var nextBlock: UnsafeMutableRawPointer
    private var thisBlockValid = false
    private var head = DeltaRing.linkBytes
    private var tail = DeltaRing.linkBytes
    private(set) var entries = 0

    init?(stateSize: Int, budgetBytes: Int) {
        guard stateSize < budgetBytes else { return nil }
        let allocation = state_delta_block_allocation(stateSize)
        let maxRecordBytes = state_delta_max_patch_size(stateSize) + Self.linkBytes * 2
        guard allocation <= budgetBytes / 2 else { return nil }
        let capacity = budgetBytes - allocation * 2
        // A ring that cannot hold one worst-case record stores nothing (state_manager.c:708-713).
        guard capacity > Self.linkBytes + maxRecordBytes else { return nil }
        blockSize = state_delta_block_size(stateSize)
        self.maxRecordBytes = maxRecordBytes
        self.capacity = capacity
        thisBlock = Self.zeroedBlock(allocation)
        nextBlock = Self.zeroedBlock(allocation)
        state_delta_mark_blocks(
            thisBlock.assumingMemoryBound(to: UInt8.self),
            nextBlock.assumingMemoryBound(to: UInt8.self),
            stateSize
        )
        data = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
    }

    deinit {
        data.deallocate()
        thisBlock.deallocate()
        nextBlock.deallocate()
    }

    private static func zeroedBlock(_ bytes: Int) -> UnsafeMutableRawPointer {
        let block = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
        block.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
        return block
    }

    var usedBytes: Int {
        head >= tail ? head - tail : capacity - tail + head
    }

    func clear() {
        head = Self.linkBytes
        tail = Self.linkBytes
        thisBlockValid = false
        entries = 0
    }

    func captureTarget() -> UnsafeMutableRawPointer {
        // The next patch must start from the newest state the ring holds (state_manager.c:673-692).
        if !thisBlockValid, pop() != nil {
            thisBlockValid = true
            entries += 1
        }
        return nextBlock
    }

    func commitCapture() {
        if thisBlockValid {
            while remainingBytes <= maxRecordBytes {
                dropOldest()
            }
            var end = head + Self.linkBytes
            end += state_delta_compress(thisBlock, nextBlock, blockSize, data + end)
            if end + maxRecordBytes > capacity {
                end = 0
                if tail == Self.linkBytes {
                    dropOldest()
                }
            }
            data.storeBytes(of: head, toByteOffset: end, as: Int.self)
            end += Self.linkBytes
            data.storeBytes(of: end, toByteOffset: head, as: Int.self)
            head = end
        } else {
            thisBlockValid = true
        }
        swap(&thisBlock, &nextBlock)
        entries += 1
    }

    func pop() -> UnsafeRawPointer? {
        if thisBlockValid {
            thisBlockValid = false
            entries -= 1
            return UnsafeRawPointer(thisBlock)
        }
        guard head != tail else { return nil }
        let start = data.loadUnaligned(fromByteOffset: head - Self.linkBytes, as: Int.self)
        guard start >= 0, start <= capacity - Self.linkBytes else { return nil }
        let patch = start + Self.linkBytes
        // A folded record keeps its patch at the buffer end, its back link at offset 0 (state_manager.c:736-751).
        let patchEnd = head == Self.linkBytes ? capacity : head - Self.linkBytes
        guard patch <= patchEnd,
              state_delta_apply(data + patch, patchEnd - patch, thisBlock, blockSize)
        else {
            return nil
        }
        head = start
        entries -= 1
        return UnsafeRawPointer(thisBlock)
    }

    private var remainingBytes: Int {
        (tail + capacity - Self.linkBytes - head - 1) % capacity + 1
    }

    private func dropOldest() {
        tail = data.loadUnaligned(fromByteOffset: tail, as: Int.self)
        entries -= 1
    }
}
