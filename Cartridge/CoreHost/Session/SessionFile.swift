import Foundation

enum SessionFile {
    static func size(atPath path: String, failureCode: CoreHostErrorCode) throws(CoreHostFailure) -> Int? {
        var info = stat()
        guard stat(path, &info) == 0 else {
            if errno == ENOENT {
                return nil
            }
            throw .posix(failureCode, "stat", errno: errno)
        }
        return Int(info.st_size)
    }

    static func read(
        atPath path: String,
        into buffer: UnsafeMutableRawPointer,
        count: Int,
        failureCode: CoreHostErrorCode
    ) throws(CoreHostFailure) {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { throw .posix(failureCode, "open", errno: errno) }
        defer { close(descriptor) }
        var total = 0
        while total < count {
            let received = Foundation.read(descriptor, buffer + total, count - total)
            if received < 0 {
                if errno == EINTR {
                    continue
                }
                throw .posix(failureCode, "read", errno: errno)
            }
            if received == 0 {
                throw CoreHostFailure(code: failureCode, message: "read: file ended after \(total) of \(count) bytes")
            }
            total += received
        }
    }

    static func writeAtomically(_ bytes: UnsafeRawBufferPointer, toPath path: String) throws(CoreHostFailure) {
        let temporary = path + ".tmp"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw writeFailure("open", errno: errno) }
        var failure: CoreHostFailure?
        var total = 0
        while total < bytes.count, failure == nil {
            let written = Foundation.write(descriptor, bytes.baseAddress.map { $0 + total }, bytes.count - total)
            if written < 0 {
                if errno != EINTR {
                    failure = writeFailure("write", errno: errno)
                }
            } else {
                total += written
            }
        }
        if failure == nil, fsync(descriptor) != 0 {
            failure = writeFailure("fsync", errno: errno)
        }
        if close(descriptor) != 0, failure == nil {
            failure = writeFailure("close", errno: errno)
        }
        if failure == nil, rename(temporary, path) != 0 {
            failure = writeFailure("rename", errno: errno)
        }
        if let failure {
            unlink(temporary)
            throw failure
        }
    }

    private static func writeFailure(_ operation: String, errno failure: Int32) -> CoreHostFailure {
        .posix(failure == ENOSPC || failure == EDQUOT ? .diskFull : .writeFailed, operation, errno: failure)
    }
}
