import Foundation

// @unchecked: the mapped pointer is immutable and every access goes through the atomic C accessors.
final class SessionAudioTap: @unchecked Sendable {
    let name: String
    private let pointer: UnsafeMutablePointer<CartridgeAudioTap>?

    var isMapped: Bool {
        pointer != nil
    }

    var sampleRate: UInt32 {
        pointer.map { cartridge_tap_sample_rate($0) } ?? 0
    }

    var samplesWritten: UInt64 {
        pointer.map { cartridge_tap_samples_written($0) } ?? 0
    }

    var tagsWritten: UInt64 {
        pointer.map { cartridge_tap_tags_written($0) } ?? 0
    }

    init(token: String) {
        name = CartridgeSharedMemoryLayout.audioTapName(for: token)
        pointer = cartridge_tap_create(name)
        if pointer == nil {
            PlayLog.session.error("tap-create-failed errno=\(errno)")
        }
    }

    deinit {
        unlink()
        if let pointer {
            cartridge_tap_unmap(pointer)
        }
    }

    func unlink() {
        guard pointer != nil else { return }
        if cartridge_tap_unlink(name) != 0, errno != ENOENT {
            PlayLog.session.error("tap-unlink-failed errno=\(errno)")
        }
    }

    func tag(at index: UInt64) -> CartridgeTapTag? {
        guard let pointer else { return nil }
        var tag = CartridgeTapTag()
        return cartridge_tap_read_tag(pointer, index, &tag) ? tag : nil
    }

    func copySamples(from frame: UInt64, count: Int, into buffer: UnsafeMutablePointer<Int16>) -> Bool {
        guard let pointer else { return false }
        return cartridge_tap_copy(pointer, frame, count, buffer)
    }
}
