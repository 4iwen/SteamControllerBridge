import Foundation
import IOKit
import IOKit.hid

struct RumbleHIDStatus: Equatable {
    var lastAttemptAt: Date?
    var attemptedDevices: Int
    var succeededDevices: Int
    var messages: [String]

    static let initial = RumbleHIDStatus(
        lastAttemptAt: nil,
        attemptedDevices: 0,
        succeededDevices: 0,
        messages: ["not sent"]
    )
}

final class ControllerConnectionService {
    var onStateChange: ((ControllerConnectionState) -> Void)?
    var onRumbleStatusChange: ((RumbleHIDStatus) -> Void)?

    private let valveVendorID = 0x28de
    private let puckProductIDs: Set<Int> = [0x1304, 0x1305, 0x1142]

    private var manager: IOHIDManager?
    private var devices: [UInt: SteamControllerDevice] = [:]
    private var hidDevices: [UInt: IOHIDDevice] = [:]
    private var reportBuffers: [UInt: UnsafeMutablePointer<UInt8>] = [:]
    private var reportBufferDeviceKeys: [UInt: UInt] = [:]
    private var state = ControllerConnectionState.notConnected
    private var rumbleTimer: DispatchSourceTimer?
    private var activeRumbleCommand: RumbleCommand?
    private var lastRumbleHIDStatus = RumbleHIDStatus.initial

    deinit {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        rumbleTimer?.cancel()

        for buffer in reportBuffers.values {
            buffer.deallocate()
        }
    }

    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }

        guard manager == nil else { return }

        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = hidManager

        IOHIDManagerSetDeviceMatching(hidManager, [
            kIOHIDVendorIDKey: valveVendorID
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, steamControllerAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, steamControllerRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("IOHIDManagerOpen failed: \(String(format: "0x%08x", result))")
        }

        addExistingDevices(from: hidManager)
        publishIfChanged()
    }

    fileprivate func add(device: IOHIDDevice) {
        let key = pointerKey(for: device)
        hidDevices[key] = device
        if devices[key] == nil {
            devices[key] = SteamControllerDevice(
                device_id: deviceID(for: device),
                name: deviceTitle(device),
                product_id: intProperty(device, key: kIOHIDProductIDKey),
                is_connected: intProperty(device, key: kIOHIDProductIDKey).map { !puckProductIDs.contains($0) } ?? false,
                last_input_at: nil,
                battery_level: nil,
                battery_voltage: nil,
                charge_state: nil,
                wireless_state: nil,
                input_state: defaultInputState()
            )
        }

        if reportBuffers[key] == nil {
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if openResult != kIOReturnSuccess {
                print("IOHIDDeviceOpen failed: \(deviceTitle(device)) \(String(format: "0x%08x", openResult))")
            }

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
            buffer.initialize(repeating: 0, count: 64)
            reportBuffers[key] = buffer
            reportBufferDeviceKeys[UInt(bitPattern: buffer)] = key
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buffer,
                64,
                steamControllerInputReportCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }

        publishIfChanged()
    }

    private func addExistingDevices(from hidManager: IOHIDManager) {
        guard let deviceSet = IOHIDManagerCopyDevices(hidManager) else { return }

        for case let device as IOHIDDevice in deviceSet as Set<NSObject> {
            add(device: device)
        }
    }

    fileprivate func remove(device: IOHIDDevice) {
        let key = pointerKey(for: device)
        devices.removeValue(forKey: key)
        hidDevices.removeValue(forKey: key)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))

        if let buffer = reportBuffers.removeValue(forKey: key) {
            reportBufferDeviceKeys.removeValue(forKey: UInt(bitPattern: buffer))
            buffer.deallocate()
        }

        publishIfChanged()
    }

    func apply(rumble command: RumbleCommand) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(rumble: command)
            }
            return
        }

        activeRumbleCommand = command
        sendRumble(command)

        if command.leftMotor == 0 && command.rightMotor == 0 {
            stopRumbleTimer()
        } else {
            startRumbleTimerIfNeeded()
        }
    }

    fileprivate func update(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) {
        let length = Int(reportLength)
        guard length > 0,
              let key = reportBufferDeviceKeys[UInt(bitPattern: report)],
              devices[key] != nil else {
            return
        }

        let firstByte = report[0]
        let type: UInt8
        let payloadOffset: Int

        if isSteamReportID(firstByte) {
            type = firstByte
            payloadOffset = 1
        } else if reportID <= UInt8.max, isSteamReportID(UInt8(reportID)) {
            type = UInt8(reportID)
            payloadOffset = 0
        } else {
            return
        }

        switch type {
        case 0x42, 0x45:
            decodeTritonState(report: report, offset: payloadOffset, length: length, key: key)
        case 0x43:
            decodeTritonBattery(report: report, offset: payloadOffset, length: length, key: key)
        case 0x46, 0x79:
            decodeTritonWireless(report: report, offset: payloadOffset, length: length, key: key)
        default:
            break
        }
    }

    private func decodeTritonState(report: UnsafeMutablePointer<UInt8>, offset: Int, length: Int, key: UInt) {
        guard offset + 45 <= length,
              let buttons = u32(report, offset + 1, length),
              let leftTrigger = i16(report, offset + 5, length),
              let rightTrigger = i16(report, offset + 7, length),
              let leftStickX = i16(report, offset + 9, length),
              let leftStickY = i16(report, offset + 11, length),
              let rightStickX = i16(report, offset + 13, length),
              let rightStickY = i16(report, offset + 15, length),
              let leftPadX = i16(report, offset + 17, length),
              let leftPadY = i16(report, offset + 19, length),
              let leftPadPressure = u16(report, offset + 21, length),
              let rightPadX = i16(report, offset + 23, length),
              let rightPadY = i16(report, offset + 25, length),
              let rightPadPressure = u16(report, offset + 27, length),
              let accelX = i16(report, offset + 33, length),
              let accelY = i16(report, offset + 35, length),
              let accelZ = i16(report, offset + 37, length),
              let gyroX = i16(report, offset + 39, length),
              let gyroY = i16(report, offset + 41, length),
              let gyroZ = i16(report, offset + 43, length) else {
            return
        }

        updateDevice(key) { device in
            device.last_input_at = Date()
            device.is_connected = true
            device.input_state.axes["left_trigger"] = Int(leftTrigger)
            device.input_state.axes["right_trigger"] = Int(rightTrigger)
            device.input_state.axes["left_stick_x"] = Int(leftStickX)
            device.input_state.axes["left_stick_y"] = Int(-leftStickY)
            device.input_state.axes["right_stick_x"] = Int(rightStickX)
            device.input_state.axes["right_stick_y"] = Int(-rightStickY)
            device.input_state.axes["left_pad_x"] = Int(leftPadX)
            device.input_state.axes["left_pad_y"] = Int(-leftPadY)
            device.input_state.axes["left_pad_pressure"] = Int(leftPadPressure)
            device.input_state.axes["right_pad_x"] = Int(rightPadX)
            device.input_state.axes["right_pad_y"] = Int(-rightPadY)
            device.input_state.axes["right_pad_pressure"] = Int(rightPadPressure)
            device.input_state.axes["accel_x"] = Int(accelX)
            device.input_state.axes["accel_y"] = Int(accelY)
            device.input_state.axes["accel_z"] = Int(accelZ)
            device.input_state.axes["gyro_x"] = Int(gyroX)
            device.input_state.axes["gyro_y"] = Int(gyroY)
            device.input_state.axes["gyro_z"] = Int(gyroZ)

            for mapping in tritonButtonMappings {
                device.input_state.buttons[mapping.name] = (buttons & mapping.mask) != 0
            }
        }
    }

    private func decodeTritonBattery(report: UnsafeMutablePointer<UInt8>, offset: Int, length: Int, key: UInt) {
        guard offset + 2 <= length else { return }

        updateDevice(key) { device in
            device.charge_state = Int(report[offset])
            device.battery_level = Int(report[offset + 1])
            device.battery_voltage = u16(report, offset + 2, length).map(Int.init)
            device.input_state.axes["battery_level"] = device.battery_level ?? 0
            device.input_state.axes["battery_voltage_mv"] = device.battery_voltage ?? 0
        }
    }

    private func decodeTritonWireless(report: UnsafeMutablePointer<UInt8>, offset: Int, length: Int, key: UInt) {
        guard offset < length else { return }

        updateDevice(key) { device in
            device.last_input_at = Date()
            let wirelessState = Int(report[offset])
            device.wireless_state = wirelessState
            if wirelessState == 1 {
                device.is_connected = false
            } else if wirelessState == 2 {
                device.is_connected = true
            }

            device.input_state.buttons["wireless_connected"] = device.is_connected
        }
    }

    private func updateDevice(_ key: UInt, mutate: (inout SteamControllerDevice) -> Void) {
        guard var device = devices[key] else { return }
        mutate(&device)
        devices[key] = device
        publishIfChanged()
    }

    private func publishIfChanged() {
        let nextDevices = mergedControllerDevices(Array(devices.values))
            .sorted { left, right in
                if left.is_connected != right.is_connected {
                    return left.is_connected
                }
                return left.device_id < right.device_id
            }

        let nextState = ControllerConnectionState(devices: nextDevices)
        guard nextState != state else { return }
        state = nextState

        DispatchQueue.main.async { [state, onStateChange] in
            onStateChange?(state)
        }
    }

    private func startRumbleTimerIfNeeded() {
        guard rumbleTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(40), repeating: .milliseconds(40))
        timer.setEventHandler { [weak self] in
            guard let self, let command = self.activeRumbleCommand else { return }
            if Date().timeIntervalSince(command.receivedAt) > 1.0 {
                self.sendRumble(leftMotor: 0, rightMotor: 0)
                self.activeRumbleCommand = nil
                self.stopRumbleTimer()
                return
            }
            self.sendRumble(command)
        }
        timer.resume()
        rumbleTimer = timer
    }

    private func stopRumbleTimer() {
        rumbleTimer?.cancel()
        rumbleTimer = nil
    }

    private func sendRumble(_ command: RumbleCommand) {
        sendRumble(leftMotor: command.leftMotor, rightMotor: command.rightMotor)
    }

    private func sendRumble(leftMotor: UInt16, rightMotor: UInt16) {
        var attemptedDevices = 0
        var succeededDevices = 0
        var messages: [String] = []

        for (key, hidDevice) in hidDevices {
            guard let device = devices[key] else { continue }
            attemptedDevices += 1
            let result = setTritonRumble(
                hidDevice,
                leftMotor: leftMotor,
                rightMotor: rightMotor
            )
            if result.succeeded {
                succeededDevices += 1
            }
            messages.append("\(device.name) \(hexTitle(device.product_id, width: 4)): \(result.message)")
        }

        if attemptedDevices == 0 {
            messages.append("no Valve HID devices open")
        }

        lastRumbleHIDStatus = RumbleHIDStatus(
            lastAttemptAt: Date(),
            attemptedDevices: attemptedDevices,
            succeededDevices: succeededDevices,
            messages: messages
        )
        onRumbleStatusChange?(lastRumbleHIDStatus)
    }

    private func setTritonRumble(_ device: IOHIDDevice, leftMotor: UInt16, rightMotor: UInt16) -> (succeeded: Bool, message: String) {
        var report: [UInt8] = [
            0x80,
            0x00,
            0x00, 0x00,
            UInt8(leftMotor & 0x00ff), UInt8((leftMotor >> 8) & 0x00ff),
            0x00,
            UInt8(rightMotor & 0x00ff), UInt8((rightMotor >> 8) & 0x00ff),
            0x00
        ]

        let reportCount = report.count
        let result = report.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(0x80),
                baseAddress,
                reportCount
            )
        }

        if result == kIOReturnSuccess {
            return (true, "sent report 0x80 len \(reportCount)")
        }

        let fallbackCount = report.count - 1
        let fallbackResult = report.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return kIOReturnBadArgument
            }
            let payloadAddress = baseAddress.advanced(by: 1)
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(0x80),
                payloadAddress,
                fallbackCount
            )
        }

        if fallbackResult == kIOReturnSuccess {
            return (true, "sent fallback report 0x80 len \(fallbackCount)")
        }

        return (
            false,
            "failed report 0x80 len \(reportCount): \(ioReturnTitle(result)); fallback: \(ioReturnTitle(fallbackResult))"
        )
    }

    private func mergedControllerDevices(_ physicalDevices: [SteamControllerDevice]) -> [SteamControllerDevice] {
        var mergedDevices: [String: SteamControllerDevice] = [:]

        for device in physicalDevices {
            let key = mergeKey(for: device)
            guard var existing = mergedDevices[key] else {
                mergedDevices[key] = device
                continue
            }

            existing = merge(existing, with: device)
            mergedDevices[key] = existing
        }

        return Array(mergedDevices.values)
    }

    private func mergeKey(for device: SteamControllerDevice) -> String {
        if device.device_id.hasPrefix("location-") {
            return device.device_id
        }

        if let voltage = device.battery_voltage {
            return "\(device.name)-battery-\(voltage)"
        }

        if let level = device.battery_level, device.charge_state != nil {
            return "\(device.name)-battery-\(level)-charge"
        }

        return device.device_id
    }

    private func merge(_ left: SteamControllerDevice, with right: SteamControllerDevice) -> SteamControllerDevice {
        var result = preferredDevice(left, right)
        let fallback = result == left ? right : left

        result.is_connected = left.is_connected || right.is_connected
        result.last_input_at = latestDate(left.last_input_at, right.last_input_at)

        let batterySource = preferredBatterySource(result, fallback)
        result.battery_level = batterySource.battery_level
        result.battery_voltage = batterySource.battery_voltage
        result.charge_state = batterySource.charge_state
        result.wireless_state = result.wireless_state ?? fallback.wireless_state
        result.input_state = merge(result.input_state, with: fallback.input_state)

        return result
    }

    private func preferredBatterySource(
        _ left: SteamControllerDevice,
        _ right: SteamControllerDevice
    ) -> SteamControllerDevice {
        if left.is_connected != right.is_connected {
            return left.is_connected ? left : right
        }

        switch (left.last_input_at, right.last_input_at) {
        case let (leftDate?, rightDate?):
            return leftDate >= rightDate ? left : right
        case (_?, nil):
            return left
        case (nil, _?):
            return right
        case (nil, nil):
            if left.battery_level != nil || right.battery_level != nil {
                return left.battery_level != nil ? left : right
            }
            return left
        }
    }

    private func preferredDevice(_ left: SteamControllerDevice, _ right: SteamControllerDevice) -> SteamControllerDevice {
        if left.is_connected != right.is_connected {
            return left.is_connected ? left : right
        }

        switch (left.last_input_at, right.last_input_at) {
        case let (leftDate?, rightDate?):
            return leftDate >= rightDate ? left : right
        case (_?, nil):
            return left
        case (nil, _?):
            return right
        case (nil, nil):
            return left
        }
    }

    private func latestDate(_ left: Date?, _ right: Date?) -> Date? {
        switch (left, right) {
        case let (leftDate?, rightDate?):
            return max(leftDate, rightDate)
        case let (leftDate?, nil):
            return leftDate
        case let (nil, rightDate?):
            return rightDate
        case (nil, nil):
            return nil
        }
    }

    private func merge(_ left: ControllerInputState, with right: ControllerInputState) -> ControllerInputState {
        var axes = left.axes
        for (key, value) in right.axes where axes[key] == nil || axes[key] == 0 {
            axes[key] = value
        }

        var buttons = left.buttons
        for (key, value) in right.buttons where buttons[key] != true {
            buttons[key] = value
        }

        return ControllerInputState(axes: axes, buttons: buttons)
    }

    private func defaultInputState() -> ControllerInputState {
        var axes: [String: Int] = [:]
        for name in steamAxisNames {
            axes[name] = 0
        }

        var buttons: [String: Bool] = [:]
        for name in steamButtonNames {
            buttons[name] = false
        }

        return ControllerInputState(axes: axes, buttons: buttons)
    }

    private func isSteamReportID(_ reportID: UInt8) -> Bool {
        switch reportID {
        case 0x42, 0x43, 0x45, 0x46, 0x79:
            return true
        default:
            return false
        }
    }

    private func pointerKey(for device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func deviceID(for device: IOHIDDevice) -> String {
        if let locationID = intProperty(device, key: kIOHIDLocationIDKey) {
            return "location-\(String(format: "%08x", locationID))"
        }

        return "hid-\(String(format: "%08lx", pointerKey(for: device)))"
    }

    private func deviceTitle(_ device: IOHIDDevice) -> String {
        stringProperty(device, key: kIOHIDProductKey) ?? "Steam Controller"
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

    private func hexTitle(_ value: Int?, width: Int) -> String {
        guard let value else { return "unknown" }
        return String(format: "0x%0\(width)x", value)
    }

    private func ioReturnTitle(_ result: IOReturn) -> String {
        String(format: "0x%08x", result)
    }

    private func u16(_ report: UnsafeMutablePointer<UInt8>, _ offset: Int, _ length: Int) -> UInt16? {
        guard offset + 2 <= length else { return nil }
        return UInt16(report[offset]) | (UInt16(report[offset + 1]) << 8)
    }

    private func i16(_ report: UnsafeMutablePointer<UInt8>, _ offset: Int, _ length: Int) -> Int16? {
        guard let value = u16(report, offset, length) else { return nil }
        return Int16(bitPattern: value)
    }

    private func u32(_ report: UnsafeMutablePointer<UInt8>, _ offset: Int, _ length: Int) -> UInt32? {
        guard offset + 4 <= length else { return nil }
        return UInt32(report[offset])
            | (UInt32(report[offset + 1]) << 8)
            | (UInt32(report[offset + 2]) << 16)
            | (UInt32(report[offset + 3]) << 24)
    }
}

private let steamControllerAddedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<ControllerConnectionService>
        .fromOpaque(context)
        .takeUnretainedValue()
        .add(device: device)
}

private let steamControllerRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<ControllerConnectionService>
        .fromOpaque(context)
        .takeUnretainedValue()
        .remove(device: device)
}

private let steamControllerInputReportCallback: IOHIDReportCallback = { context, result, _, _, reportID, report, reportLength in
    guard let context, result == kIOReturnSuccess else { return }
    Unmanaged<ControllerConnectionService>
        .fromOpaque(context)
        .takeUnretainedValue()
        .update(reportID: reportID, report: report, reportLength: reportLength)
}

private let steamAxisNames = [
    "left_trigger",
    "right_trigger",
    "left_stick_x",
    "left_stick_y",
    "right_stick_x",
    "right_stick_y",
    "left_pad_x",
    "left_pad_y",
    "left_pad_pressure",
    "right_pad_x",
    "right_pad_y",
    "right_pad_pressure",
    "accel_x",
    "accel_y",
    "accel_z",
    "gyro_x",
    "gyro_y",
    "gyro_z",
    "battery_level",
    "battery_voltage_mv"
]

private let steamButtonNames = [
    "a",
    "b",
    "x",
    "y",
    "quick_access",
    "left_stick_click",
    "right_stick_click",
    "view",
    "menu",
    "steam",
    "left_shoulder",
    "right_shoulder",
    "dpad_up",
    "dpad_down",
    "dpad_left",
    "dpad_right",
    "left_paddle_1",
    "left_paddle_2",
    "right_paddle_1",
    "right_paddle_2",
    "left_pad_touch",
    "left_pad_click",
    "right_pad_touch",
    "right_pad_click",
    "left_trigger_click",
    "right_trigger_click",
    "left_stick_touch",
    "right_stick_touch",
    "left_grip_touch",
    "right_grip_touch",
    "wireless_connected"
]

private let tritonButtonMappings: [(name: String, mask: UInt32)] = [
    ("a", 0x00000001),
    ("b", 0x00000002),
    ("x", 0x00000004),
    ("y", 0x00000008),
    ("quick_access", 0x00000010),
    ("right_stick_click", 0x00000020),
    ("view", 0x00000040),
    ("right_paddle_1", 0x00000080),
    ("right_paddle_2", 0x00000100),
    ("right_shoulder", 0x00000200),
    ("dpad_down", 0x00000400),
    ("dpad_right", 0x00000800),
    ("dpad_left", 0x00001000),
    ("dpad_up", 0x00002000),
    ("menu", 0x00004000),
    ("left_stick_click", 0x00008000),
    ("steam", 0x00010000),
    ("left_paddle_1", 0x00020000),
    ("left_paddle_2", 0x00040000),
    ("left_shoulder", 0x00080000),
    ("right_stick_touch", 0x00100000),
    ("right_pad_touch", 0x00200000),
    ("right_pad_click", 0x00400000),
    ("right_trigger_click", 0x00800000),
    ("left_stick_touch", 0x01000000),
    ("left_pad_touch", 0x02000000),
    ("left_pad_click", 0x04000000),
    ("left_trigger_click", 0x08000000),
    ("right_grip_touch", 0x10000000),
    ("left_grip_touch", 0x20000000)
]
