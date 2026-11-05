import Foundation
import IOKit.hid

@MainActor
final class HIDTransportProbe {
    var onChange: (() -> Void)?

    private static let sonyVendorID = 0x054C
    private static let dualSenseProductID = 0x0CE6

    private var manager: IOHIDManager?
    private var transports: [ObjectIdentifier: String] = [:]

    var transport: ControllerTransport {
        let distinct = Set(transports.values)
        guard distinct.count == 1, let value = distinct.first else { return .unknown }
        switch value {
        case "Bluetooth": return .bluetooth
        case "USB": return .usb
        default: return .unknown
        }
    }

    isolated deinit {
        if let manager {
            IOHIDManagerCancel(manager)
        }
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Int] = [
            kIOHIDVendorIDKey: Self.sonyVendorID,
            kIOHIDProductIDKey: Self.dualSenseProductID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let matched: IOHIDDeviceCallback = { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDTransportProbe>.fromOpaque(context).takeUnretainedValue().added(device)
            }
        }
        let removed: IOHIDDeviceCallback = { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDTransportProbe>.fromOpaque(context).takeUnretainedValue().removed(device)
            }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removed, context)
        IOHIDManagerSetDispatchQueue(manager, DispatchQueue.main)
        IOHIDManagerActivate(manager)
        self.manager = manager
    }

    private func added(_ device: IOHIDDevice) {
        let value = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        transports[ObjectIdentifier(device)] = value ?? ""
        onChange?()
    }

    private func removed(_ device: IOHIDDevice) {
        transports[ObjectIdentifier(device)] = nil
        onChange?()
    }
}
