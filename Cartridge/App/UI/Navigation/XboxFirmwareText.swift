import Foundation

struct XboxFirmwareLine: Equatable, Identifiable {
    let kind: MessageKind
    let lead: String
    let rest: String

    var id: String {
        lead
    }
}

extension XboxFirmwareFile {
    var chipName: String {
        switch self {
        case .bootROM: "MCPX 1.0 boot ROM"
        case .flash: "Complex 4627 BIOS"
        }
    }

    var chipDetail: String {
        switch self {
        case .bootROM: "512 bytes"
        case .flash: "256 KB, 512 KB or 1 MB"
        }
    }

    var importedName: String {
        switch self {
        case .bootROM: "the boot ROM"
        case .flash: "Complex 4627"
        }
    }

    func status(isReady: Bool) -> String {
        switch self {
        case .bootROM: isReady ? "Boot ROM ready" : "Boot ROM needed"
        case .flash: isReady ? "Complex 4627 ready" : "Complex 4627 BIOS needed"
        }
    }
}

extension XboxFirmwareImport {
    func lines(installed: Set<XboxFirmwareFile>) -> [XboxFirmwareLine] {
        if imported.isEmpty, refused.isEmpty {
            let none = XboxFirmwareLine(
                kind: .warning,
                lead: "No Xbox BIOS files in \(folderName) (\(filesChecked.formatted()) files checked).",
                rest: "Cartridge needs the MCPX 1.0 boot ROM and the Complex 4627 BIOS."
            )
            return [none]
        }
        var lines: [XboxFirmwareLine] = []
        if !imported.isEmpty {
            lines.append(XboxFirmwareLine(
                kind: .success,
                lead: "Imported \(imported.map(\.importedName).sentenceList) from \(folderName).",
                rest: Self.restAfterImport(installed: installed)
            ))
        }
        return lines + refused.map(Self.line(for:))
    }

    private static func restAfterImport(installed: Set<XboxFirmwareFile>) -> String {
        if installed.isSuperset(of: XboxFirmwareFile.allCases) {
            return "Xbox games are ready to play."
        }
        return installed.contains(.bootROM)
            ? "Cartridge still needs the Complex 4627 BIOS."
            : "Cartridge still needs the MCPX 1.0 boot ROM."
    }

    private static func line(for refusal: XboxFirmwareRefusal) -> XboxFirmwareLine {
        let file = refusal.fileName
        return switch refusal.reason {
        case .damagedBootROM:
            XboxFirmwareLine(
                kind: .warning,
                lead: "\(file) is a damaged copy of the Xbox boot ROM.",
                rest: "Cartridge needs an exact copy of the MCPX 1.0 boot ROM."
            )
        case .bootROM11:
            XboxFirmwareLine(
                kind: .warning,
                lead: "\(file) is the MCPX 1.1 boot ROM.",
                rest: "Cartridge needs the 1.0 boot ROM."
            )
        case .retailBIOS:
            XboxFirmwareLine(
                kind: .warning,
                lead: "\(file) is an unmodified Xbox BIOS.",
                rest: "It can’t start games. Cartridge needs Complex 4627."
            )
        case .unknownBIOS:
            XboxFirmwareLine(
                kind: .warning,
                lead: "Cartridge doesn’t know the Xbox BIOS \(file).",
                rest: "Cartridge needs Complex 4627."
            )
        }
    }
}
