import SwiftUI

struct SettingsScreen: View {
    let model: AppModel

    var body: some View {
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: [
                Hint(kind: .sections, label: "Sections"),
                Hint(kind: .row, label: "Move"),
                Hint(kind: .confirm, label: "Select"),
                Hint(kind: .back, label: "Back"),
            ],
            bar: model.shellBar,
            backdrop: { CinematicBackdrop(source: .collage, style: .detail, heightFraction: 1) },
            content: {
                HStack(alignment: .top, spacing: Space.n7) {
                    VStack(alignment: .leading, spacing: Space.n5) {
                        Text("Settings")
                            .typeStyle(.titleL)
                            .foregroundStyle(Palette.textPrimary)
                        Text(description)
                            .typeStyle(.body)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: Layout.settingsLeftWidth, alignment: .leading)
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            SettingsRows(model: model)
                                .padding(.vertical, Space.n3)
                                .padding(.bottom, Layout.hintbarHeight)
                        }
                        .onChange(of: model.settingsFocus) {
                            withAnimation(Motion.easeOut(Motion.scroll)) {
                                proxy.scrollTo(model.settingsFocus, anchor: .center)
                            }
                        }
                    }
                }
                .padding(.horizontal, Layout.marginX)
                .padding(.top, model.chrome.safeTop + Space.n2 + Layout.topbarHeight + Space.n6)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        )
    }

    private var description: String {
        switch SettingsRowID(rawValue: model.settingsFocus) ?? .romFolder {
        case .romFolder:
            "Cartridge reads games from this folder and never changes, moves or adds files in it."
        case .rescan:
            model.isRescanning
                ? "Cartridge is reading the folder again. New games appear in the library as they are found; "
                    + "removed ones disappear when the scan ends."
                : "Cartridge reads the folder again and adds or removes games to match."
        case .bios:
            "Point Cartridge at the folder that holds scph5500.bin, scph5501.bin or scph5502.bin. "
                + "It copies the file and leaves the original where it is."
        case .xboxBIOS:
            "Point Cartridge at the folder that holds your Xbox boot ROM and Complex 4627 BIOS. "
                + "It checks every file in the folder by what is inside it, copies the two it needs "
                + "and leaves the originals where they are. Cartridge makes the Xbox hard drive itself."
        case .controller:
            "See what every button on the DualSense does, in menus and in games."
        case .introSound:
            "The boot sound that plays with the Cartridge intro each time the app opens."
        case .interfaceSounds:
            "Soft clicks as you move, select and go back. Turn them off for a silent menu."
        case .about:
            "Version, credits and the licenses of the software inside Cartridge."
        }
    }
}

private struct SettingsRows: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                GroupHeading(text: "Library")
                SettingsRow(
                    glyph: .symbol("folder"),
                    label: "ROM folder",
                    detail: AppModel.abbreviated(model.folderPath),
                    trailing: .text("Change…"),
                    state: state(.romFolder)
                )
                .id(SettingsRowID.romFolder.rawValue)
                .padding(.bottom, Space.n2)
                rescanRow
                    .id(SettingsRowID.rescan.rawValue)
                GroupHeading(text: "PS1")
                biosRow
                    .id(SettingsRowID.bios.rawValue)
            }
            Group {
                GroupHeading(text: "Xbox")
                xboxRow
                    .id(SettingsRowID.xboxBIOS.rawValue)
                GroupHeading(text: "Controller")
                controllerRow
                    .id(SettingsRowID.controller.rawValue)
                GroupHeading(text: "Sound")
                soundRow(.introSound, key: .introSound, label: "Intro sound", glyph: "speaker.wave.2")
                    .id(SettingsRowID.introSound.rawValue)
                    .padding(.bottom, Space.n2)
                soundRow(.interfaceSounds, key: .interfaceSounds, label: "Interface sounds", glyph: "hand.tap")
                    .id(SettingsRowID.interfaceSounds.rawValue)
            }
            SettingsRow(
                glyph: .symbol("info.circle"),
                label: "About Cartridge",
                detail: AppVersion.line.map { "Version \($0), credits and licenses" } ?? "Credits and licenses",
                trailing: .chevron,
                state: state(.about)
            )
            .id(SettingsRowID.about.rawValue)
            .padding(.top, Space.n6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func soundRow(_ row: SettingsRowID, key: DefaultsKey, label: String, glyph: String) -> some View {
        SettingsRow(
            glyph: .symbol(glyph),
            label: label,
            detail: nil,
            trailing: .text(model.isSoundOn(key) ? "On" : "Off"),
            state: state(row)
        )
    }

    private func state(_ row: SettingsRowID) -> SettingsRowState {
        if !model.isSettingsRowEnabled(row) {
            return .disabled
        }
        return model.settingsFocus == row.rawValue ? .highlighted : .resting
    }

    @ViewBuilder private var rescanRow: some View {
        if let scan = model.scan, model.isRescanning {
            SettingsRow(
                glyph: .symbol("arrow.clockwise"),
                label: "Rescanning…",
                detail: "Checked \(scan.filesChecked.formatted()) of \(scan.filesFound.formatted()) files",
                accessory: .spinner,
                state: .disabled
            )
        } else {
            SettingsRow(
                glyph: .symbol("arrow.clockwise"),
                label: "Rescan Library",
                detail: model.lastScan.map {
                    "Last scanned \(DisplayDate.text($0.date)). \(LibraryRows.gameCount($0.games))."
                },
                state: state(.rescan)
            )
        }
    }

    @ViewBuilder private var biosRow: some View {
        let regions = model.biosStatus
        SettingsRow(
            glyph: .symbol("cpu"),
            label: "PS1 BIOS",
            detail: regions.isEmpty
                ? "None. PS1 games use the built-in replacement."
                : "Ready: \(regions.map(\.displayName).sentenceList)",
            accessory: regions.isEmpty ? .none : .success,
            trailing: .text("Choose Folder…"),
            state: state(.bios)
        )
        if let result = model.biosResult {
            BIOSResultView(result: result)
                .padding(.top, Space.n2)
        }
    }

    @ViewBuilder private var xboxRow: some View {
        let installed = model.xboxFirmwareInstalled
        SettingsRow(
            glyph: .symbol("cpu"),
            label: "Xbox BIOS",
            detail: nil,
            statuses: XboxFirmwareFile.allCases.map { file in
                let isReady = installed.contains(file)
                return SettingsStatus(text: file.status(isReady: isReady), isReady: isReady)
            },
            trailing: .text("Choose Folder…"),
            state: state(.xboxBIOS)
        )
        if let result = model.xboxFirmwareImport {
            VStack(alignment: .leading, spacing: Space.n2) {
                ForEach(result.lines(installed: installed)) { line in
                    InlineResult(kind: line.kind, lead: line.lead, rest: line.rest)
                }
            }
            .padding(.top, Space.n2)
        }
    }

    private var controllerRow: some View {
        let controller = model.chrome.controller
        return SettingsRow(
            glyph: controller == nil ? .noController : .symbol("gamecontroller.fill"),
            label: "Controller guide",
            detail: controller.map { "\($0.name), \(Self.connection($0.transport))" }
                ?? "Not connected. Pair a DualSense in System Settings › Bluetooth.",
            trailing: .chevron,
            state: state(.controller)
        )
    }

    private static func connection(_ transport: ControllerTransport) -> String {
        switch transport {
        case .bluetooth: "connected over Bluetooth"
        case .usb: "connected with a USB cable"
        case .unknown: "connected"
        }
    }
}

private struct GroupHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .typeStyle(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.textSecondary)
            .padding(.leading, Space.n5)
            .padding(.top, Space.n6)
            .padding(.bottom, Space.n2)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct BIOSResultView: View {
    let result: BIOSImportResult

    var body: some View {
        if let failure = BIOSFailureText(result) {
            InlineResult(kind: .warning, lead: failure.lead, rest: Self.settingsRest(result) ?? failure.rest)
        } else if case .imported(let regions, _) = result {
            InlineResult(
                kind: .success,
                lead: "Imported \(regions.map(\.rawValue).sentenceList).",
                rest: "PS1 is ready for \(regions.map(\.displayName).sentenceList)."
            )
        }
    }

    private static func settingsRest(_ result: BIOSImportResult) -> String? {
        guard case .noneFound = result else { return nil }
        return "Cartridge looks for scph5500.bin, scph5501.bin or scph5502.bin."
    }
}

enum AppVersion {
    static var line: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String
        else { return nil }
        return "\(short) (\(build))"
    }
}
