import Foundation

struct BatterySave {
    let library: CoreLibrary
    let path: String

    var size: Int {
        library.saveRAM()?.size ?? 0
    }

    func restore() throws(CoreHostFailure) {
        guard let memory = library.saveRAM(),
              let fileSize = try SessionFile.size(atPath: path, failureCode: .contentLoadFailed)
        else {
            CoreHostLog.session.notice("battery-restored bytes=0")
            return
        }
        let count = min(fileSize, memory.size)
        try SessionFile.read(atPath: path, into: memory.pointer, count: count, failureCode: .contentLoadFailed)
        CoreHostLog.session.notice("battery-restored bytes=\(count)")
    }

    func write() throws(CoreHostFailure) -> Bool {
        guard let memory = library.saveRAM() else {
            return false
        }
        try SessionFile.writeAtomically(UnsafeRawBufferPointer(start: memory.pointer, count: memory.size), toPath: path)
        return true
    }
}
