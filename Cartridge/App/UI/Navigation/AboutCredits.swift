import Foundation

struct CreditRow: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String {
        label
    }
}

struct LicenseText: Identifiable, Equatable {
    let name: String
    let paragraphs: [String]

    var id: String {
        name
    }
}

struct AboutCredits: Equatable {
    var emulation: [CreditRow] = []
    var licenses: [LicenseText] = []

    static let cheatData = CreditRow(
        label: "libretro cheats",
        value: "Cheat lists from libretro-database (commit 12c21cf), CC BY-SA 4.0"
    )

    private struct Source {
        let system: GameSystem
        let core: String
        let file: String
    }

    private static let sources = [
        Source(system: .nes, core: "Mesen", file: "mesen"),
        Source(system: .snes, core: "Snes9x", file: "snes9x"),
        Source(system: .genesis, core: "Genesis Plus GX", file: "genesis-plus-gx"),
        Source(system: .n64, core: "Mupen64Plus-Next", file: "mupen64plus-next"),
        Source(system: .ps1, core: "Beetle PSX", file: "beetle-psx"),
    ]

    private static let xemuVersion = "0.8.139"
    private static let thirdPartyMarker = "xemu depends on several great packages/libraries"

    private static let xemuPatches = [
        "Depth-precision fast path (catskull c5fa9ff4)",
        "Shared-library build",
        "Headless host: display, input and audio for Cartridge",
        "Redump discs read in place",
        "libfatx: retail E partition size",
    ]

    private static let xemuLicenseName = "xemu (GNU GPL v2 and third-party notices)"

    @concurrent
    static func load() async -> AboutCredits {
        let log = LogChannel(category: "library")
        var credits = AboutCredits()
        for source in sources {
            guard let text = read(source.file, log: log) else { continue }
            let license = licenseName(of: text, core: source.core)
            credits.emulation.append(CreditRow(label: source.system.displayName, value: "\(source.core), \(license)"))
            if !credits.licenses.contains(where: { $0.name == license }) {
                credits.licenses.append(LicenseText(name: license, paragraphs: paragraphs(of: text)))
            }
        }
        if let text = read("xemu", log: log) {
            credits.emulation += xemuRows(license: licenseName(of: text, core: "xemu"))
            credits.licenses.append(LicenseText(name: xemuLicenseName, paragraphs: paragraphs(of: text)))
        }
        if let text = read("libretro-database", log: log) {
            let license = licenseName(of: text, core: "libretro-database")
            credits.licenses.append(LicenseText(name: license, paragraphs: paragraphs(of: text)))
        }
        return credits
    }

    private static func xemuRows(license: String) -> [CreditRow] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let archive = version.map { "Cartridge-\($0)-xemu-src.tar.gz" } ?? "Cartridge-<version>-xemu-src.tar.gz"
        return [
            CreditRow(label: "Xbox", value: "xemu \(xemuVersion), \(license)"),
            CreditRow(label: "xemu changes", value: xemuPatches.joined(separator: "; ")),
            CreditRow(
                label: "xemu source",
                value: "The exact source of this build, with every change above, "
                    + "is published next to each Cartridge release as \(archive)."
            ),
            CreditRow(
                label: "xemu libraries",
                value: "glib, libintl (gettext), libiconv and libusb are used under the GNU LGPL 2.1; "
                    + "their source and the other bundled libraries’ source are in \(archive)"
            ),
        ]
    }

    private static func read(_ name: String, log: LogChannel) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses") else {
            log.error("license-missing name=\(name)")
            return nil
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            log
                .error(
                    "license-unreadable name=\(name) \(error.localizedDescription)"
                )
            return nil
        }
    }

    private static func licenseName(of text: String, core: String) -> String {
        let head = text.components(separatedBy: thirdPartyMarker)[0]
        if head.contains("GNU GENERAL PUBLIC LICENSE") {
            return head.contains("Version 3") ? "GNU GPL v3" : "GNU GPL v2"
        }
        if text.contains("Attribution-ShareAlike 4.0") {
            return "CC BY-SA 4.0"
        }
        return text.localizedCaseInsensitiveContains("commercial")
            ? "\(core) license (non-commercial)"
            : "\(core) license"
    }

    private static func paragraphs(of text: String) -> [String] {
        text.components(separatedBy: "\n\n").compactMap { block in
            let words = block.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return words.isEmpty ? nil : words
        }
    }
}
