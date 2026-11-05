import Foundation

final class StateStore {
    private let library: CoreLibrary
    private var buffer: UnsafeMutableRawPointer?
    private var capacity = 0

    init(library: CoreLibrary) {
        self.library = library
    }

    deinit {
        buffer?.deallocate()
    }

    func save(toPath path: String) throws(CoreHostFailure) {
        let buffer = try prepareBuffer(failureCode: .serializeFailed)
        let reported = library.serializeSize()
        let size = min(reported, capacity)
        if size < reported {
            CoreHostLog.session.error("serialize size grew to \(reported), keeping \(size)")
        }
        guard library.serialize(into: buffer, size: size) else {
            throw CoreHostFailure(code: .serializeFailed, message: "retro_serialize returned false")
        }
        try SessionFile.writeAtomically(UnsafeRawBufferPointer(start: buffer, count: size), toPath: path)
    }

    func load(fromPath path: String) throws(CoreHostFailure) {
        let buffer = try prepareBuffer(failureCode: .unserializeFailed)
        guard let size = try SessionFile.size(atPath: path, failureCode: .unserializeFailed), size > 0 else {
            throw CoreHostFailure(code: .unserializeFailed, message: "state file missing or empty")
        }
        guard size <= capacity else {
            throw CoreHostFailure(
                code: .unserializeFailed,
                message: "state file \(size) bytes exceeds buffer \(capacity)"
            )
        }
        try SessionFile.read(atPath: path, into: buffer, count: size, failureCode: .unserializeFailed)
        // Mupen64Plus-Next's retro_unserialize returns true on failure; the result is taken as-is.
        guard library.unserialize(from: buffer, size: size) else {
            throw CoreHostFailure(code: .unserializeFailed, message: "retro_unserialize returned false")
        }
    }

    private func prepareBuffer(failureCode: CoreHostErrorCode) throws(CoreHostFailure) -> UnsafeMutableRawPointer {
        if let buffer {
            return buffer
        }
        let size = library.serializeSize()
        guard size > 0 else {
            throw CoreHostFailure(code: failureCode, message: "core does not support save states")
        }
        let allocated = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        buffer = allocated
        capacity = size
        return allocated
    }
}
