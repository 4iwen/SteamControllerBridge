import Foundation
import IOKit
import IOKit.hid

final class PuckDetectorService {
    var onStateChange: ((PuckState) -> Void)?

    private let valveVendorID = 0x28de
    private let primaryProductIDs: Set<Int> = [0x1304, 0x1305]
    private let legacyProductIDs: Set<Int> = [0x1142]

    private var manager: IOHIDManager?
    private var state = PuckState.notDetected
    private var records: [DeviceKey: DeviceRecord] = [:]
    private var interfaceKeys: [UInt: DeviceKey] = [:]

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
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, deviceAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, deviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))

        updateState()
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

        if var record = records[deviceKey] {
            record.interfaceCount += 1
            records[deviceKey] = record
        } else {
            records[deviceKey] = DeviceRecord(
                state: PuckState(
                    is_present: true,
                    vendor_id: intProperty(device, key: kIOHIDVendorIDKey),
                    product_id: productID,
                    product_name: stringProperty(device, key: kIOHIDProductKey),
                    manufacturer: stringProperty(device, key: kIOHIDManufacturerKey),
                    transport: stringProperty(device, key: kIOHIDTransportKey),
                    location_id: intProperty(device, key: kIOHIDLocationIDKey),
                    is_legacy: legacyProductIDs.contains(productID)
                ),
                interfaceCount: 1
            )
        }

        updateState()
    }

    fileprivate func remove(device: IOHIDDevice) {
        let pointerKey = pointerKey(for: device)
        guard let deviceKey = interfaceKeys.removeValue(forKey: pointerKey),
              var record = records[deviceKey] else {
            return
        }

        record.interfaceCount -= 1
        if record.interfaceCount > 0 {
            records[deviceKey] = record
        } else {
            records.removeValue(forKey: deviceKey)
        }

        updateState()
    }

    private func updateState() {
        let nextState = records.values
            .sorted { left, right in
                if left.state.is_legacy != right.state.is_legacy {
                    return !left.state.is_legacy
                }

                return (left.state.product_id ?? 0) < (right.state.product_id ?? 0)
            }
            .first?
            .state ?? .notDetected

        guard nextState != state else { return }
        state = nextState
        DispatchQueue.main.async { [state, onStateChange] in
            onStateChange?(state)
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

private let deviceAddedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<PuckDetectorService>
        .fromOpaque(context)
        .takeUnretainedValue()
        .add(device: device)
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<PuckDetectorService>
        .fromOpaque(context)
        .takeUnretainedValue()
        .remove(device: device)
}

private struct DeviceKey: Hashable {
    enum Kind: Hashable {
        case locationID
        case registryEntryID
        case interfacePointer
    }

    let productID: Int
    let value: UInt64
    let kind: Kind
}

private struct DeviceRecord {
    var state: PuckState
    var interfaceCount: Int
}
