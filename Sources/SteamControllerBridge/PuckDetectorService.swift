import Foundation
import IOKit
import IOKit.hid

final class PuckDetectorService {
    var onStateChange: (([PuckState]) -> Void)?

    private let valveVendorID = 0x28de
    private let primaryProductIDs: Set<Int> = [0x1304, 0x1305]
    private let legacyProductIDs: Set<Int> = [0x1142]

    private var manager: IOHIDManager?
    private var states: [DeviceKey: PuckState] = [:]
    private var interfaceCounts: [DeviceKey: Int] = [:]
    private var interfaceKeys: [UInt: DeviceKey] = [:]
    private var publishedStates: [PuckState] = []

    deinit {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func start() {
        guard manager == nil else { return }

        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = hidManager

        IOHIDManagerSetDeviceMatchingMultiple(hidManager, matchingDictionaries() as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, puckDeviceAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, puckDeviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))

        publishIfChanged()
    }

    private func matchingDictionaries() -> [[String: Int]] {
        (primaryProductIDs.union(legacyProductIDs)).map { productID in
            [
                kIOHIDVendorIDKey: valveVendorID,
                kIOHIDProductIDKey: productID
            ]
        }
    }

    fileprivate func add(device: IOHIDDevice) {
        guard let productID = intProperty(device, key: kIOHIDProductIDKey),
              primaryProductIDs.contains(productID) || legacyProductIDs.contains(productID) else {
            return
        }

        let pointerKey = pointerKey(for: device)
        let deviceKey = dedupeKey(for: device, productID: productID)
        interfaceKeys[pointerKey] = deviceKey

        interfaceCounts[deviceKey, default: 0] += 1
        if states[deviceKey] == nil {
            states[deviceKey] = PuckState(
                device_id: deviceKey.title,
                is_present: true,
                vendor_id: intProperty(device, key: kIOHIDVendorIDKey),
                product_id: productID,
                product_name: stringProperty(device, key: kIOHIDProductKey),
                manufacturer: stringProperty(device, key: kIOHIDManufacturerKey),
                transport: stringProperty(device, key: kIOHIDTransportKey),
                location_id: intProperty(device, key: kIOHIDLocationIDKey),
                is_legacy: legacyProductIDs.contains(productID)
            )
        }

        publishIfChanged()
    }

    fileprivate func remove(device: IOHIDDevice) {
        let pointerKey = pointerKey(for: device)
        guard let deviceKey = interfaceKeys.removeValue(forKey: pointerKey) else {
            return
        }

        let nextCount = max((interfaceCounts[deviceKey] ?? 1) - 1, 0)
        if nextCount > 0 {
            interfaceCounts[deviceKey] = nextCount
        } else {
            interfaceCounts.removeValue(forKey: deviceKey)
            states.removeValue(forKey: deviceKey)
        }

        publishIfChanged()
    }

    private func publishIfChanged() {
        let nextStates = states.values.sorted { left, right in
            if left.is_legacy != right.is_legacy {
                return !left.is_legacy
            }

            if left.product_id != right.product_id {
                return (left.product_id ?? 0) < (right.product_id ?? 0)
            }

            return left.device_id < right.device_id
        }

        guard nextStates != publishedStates else { return }
        publishedStates = nextStates
        DispatchQueue.main.async { [publishedStates, onStateChange] in
            onStateChange?(publishedStates)
        }
    }

    private func pointerKey(for device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func dedupeKey(for device: IOHIDDevice, productID: Int) -> DeviceKey {
        if let locationID = intProperty(device, key: kIOHIDLocationIDKey) {
            return DeviceKey(productID: productID, value: UInt64(UInt32(truncatingIfNeeded: locationID)), kind: .locationID)
        }

        if let registryID = registryEntryID(for: device) {
            return DeviceKey(productID: productID, value: registryID, kind: .registryEntryID)
        }

        return DeviceKey(productID: productID, value: UInt64(pointerKey(for: device)), kind: .interfacePointer)
    }

    private func intProperty(_ device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }

        if CFGetTypeID(value) == CFNumberGetTypeID() {
            var result: Int = 0
            guard CFNumberGetValue((value as! CFNumber), .intType, &result) else { return nil }
            return result
        }

        return nil
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString),
              CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }

        return value as? String
    }

    private func registryEntryID(for device: IOHIDDevice) -> UInt64? {
        let service = IOHIDDeviceGetService(device)
        guard service != 0 else { return nil }

        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
        return entryID
    }
}

private let puckDeviceAddedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<PuckDetectorService>
        .fromOpaque(context)
        .takeUnretainedValue()
        .add(device: device)
}

private let puckDeviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<PuckDetectorService>
        .fromOpaque(context)
        .takeUnretainedValue()
        .remove(device: device)
}

private struct DeviceKey: Hashable {
    enum Kind: String, Hashable {
        case locationID
        case registryEntryID
        case interfacePointer
    }

    let productID: Int
    let value: UInt64
    let kind: Kind

    var title: String {
        "\(kind.rawValue)-\(String(format: "%04x", productID))-\(String(format: "%llx", value))"
    }
}
