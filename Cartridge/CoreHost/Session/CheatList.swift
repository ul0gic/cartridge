import Foundation

enum CheatReapplyEvent: String {
    case reset
    case load
    case rewind
}

final class CheatList {
    private static let maxCodeLength = 255
    private static let printable: ClosedRange<UInt8> = 0x20...0x7E
    private static let genesisPlusGXCore = "genesis_plus_gx_libretro.dylib"
    /// MAX_CHEATS, shared by every code of one list (Genesis-Plus-GX libretro/libretro.c:171).
    private static let genesisPlusGXMaxCodes = 150

    private let library: CoreLibrary
    private let limitsCodeCount: Bool
    private(set) var codes: [String] = []

    init(library: CoreLibrary, corePath: String) {
        self.library = library
        limitsCodeCount = (corePath as NSString).lastPathComponent == Self.genesisPlusGXCore
    }

    func set(_ codes: [String]) throws(CoreHostFailure) {
        if let reason = rejection(of: codes) {
            throw CoreHostFailure(code: .cheatRejected, message: "cheats-rejected reason=\(reason)")
        }
        apply(codes)
        self.codes = codes
        CoreHostLog.session.notice("cheats-set count=\(codes.count)")
    }

    func reapply() {
        apply(codes)
    }

    private func apply(_ codes: [String]) {
        library.cheatReset()
        for (index, code) in codes.enumerated() {
            library.cheatSet(index: UInt32(index), enabled: true, code: code)
        }
    }

    private func rejection(of codes: [String]) -> String? {
        for code in codes {
            let bytes = code.utf8
            if bytes.isEmpty {
                return "empty"
            }
            if bytes.count >= Self.maxCodeLength {
                return "too-long"
            }
            if !bytes.allSatisfy(Self.printable.contains) {
                return "not-printable"
            }
        }
        if limitsCodeCount, codes.reduce(0, { $0 + $1.split(separator: "+").count }) > Self.genesisPlusGXMaxCodes {
            return "too-many"
        }
        return nil
    }
}
