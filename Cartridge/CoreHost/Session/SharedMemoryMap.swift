import Foundation

struct SharedMemoryMap {
    let pointer: UnsafeMutablePointer<CartridgeSharedMemory>

    init(name: String) throws(CoreHostFailure) {
        guard name.hasPrefix(CartridgeSharedMemoryLayout.name(for: "")) else {
            throw CoreHostFailure(code: .sharedMemoryUnavailable, message: "unexpected shared memory name")
        }
        guard let pointer = cartridge_shm_open(name) else {
            throw .posix(.sharedMemoryUnavailable, "shm_open", errno: errno)
        }
        self.pointer = pointer
    }

    func unmap() {
        cartridge_shm_unmap(pointer)
    }
}
