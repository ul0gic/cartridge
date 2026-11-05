import AppKit
import IOKit.ps

@MainActor
enum SystemConditions {
    static var build: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let bundleVersion = info?["CFBundleVersion"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "app=\(version)(\(bundleVersion)) macos=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    static var power: String {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0
        return "thermal=\(thermalState) low-power=\(lowPower) power=\(powerSource)"
    }

    static var focus: String {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        return "frontmost=\(frontmost) app-active=\(NSApplication.shared.isActive ? 1 : 0)"
    }

    static var displayHz: String {
        NSScreen.main.map { String($0.maximumFramesPerSecond) } ?? "unknown"
    }

    private static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static var powerSource: String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return "unknown" }
        switch source as String {
        case kIOPMACPowerKey: return "ac"
        case kIOPMBatteryPowerKey: return "battery"
        case kIOPMUPSPowerKey: return "ups"
        default: return "unknown"
        }
    }
}
