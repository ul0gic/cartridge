public enum CartridgeSharedMemoryLayout {
    public static let size = Int(CARTRIDGE_SHM_SIZE)

    private static let prefix = "/cartridge-"
    private static let tokenLength = 8

    public static func name(for sessionToken: String) -> String {
        prefix + sessionToken
    }

    public static func audioTapName(for sessionToken: String) -> String {
        prefix + sessionToken + "-a"
    }

    public static func sessionToken(fromName name: String) -> String? {
        guard name.hasPrefix(prefix) else { return nil }
        let token = name.dropFirst(prefix.count)
        guard token.count == tokenLength, token.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return String(token)
    }
}
