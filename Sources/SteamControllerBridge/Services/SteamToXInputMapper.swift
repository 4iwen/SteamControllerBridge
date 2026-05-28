import Foundation

struct SteamToXInputMapper {
    func map(controllerState: ControllerConnectionState, packetNumber: UInt32 = 0) -> XInputControllerState {
        guard let controller = controllerState.connectedDevices.first else {
            var disconnected = XInputControllerState.disconnected
            disconnected.packetNumber = packetNumber
            return disconnected
        }

        return map(device: controller, packetNumber: packetNumber)
    }

    func map(device: SteamControllerDevice, packetNumber: UInt32 = 0) -> XInputControllerState {
        let input = device.input_state
        return XInputControllerState(
            isConnected: device.is_connected,
            packetNumber: packetNumber,
            buttons: buttons(from: input),
            leftTrigger: trigger(from: input.axes["left_trigger"]),
            rightTrigger: trigger(from: input.axes["right_trigger"]),
            leftThumbX: thumbAxis(from: input.axes["left_stick_x"]),
            leftThumbY: thumbAxis(from: input.axes["left_stick_y"]),
            rightThumbX: thumbAxis(from: input.axes["right_stick_x"]),
            rightThumbY: thumbAxis(from: input.axes["right_stick_y"]),
            batteryPercent: percent(from: device.battery_level ?? input.axes["battery_level"]),
            batteryVoltage: voltage(from: device.battery_voltage ?? input.axes["battery_voltage_mv"])
        )
    }

    private func buttons(from input: ControllerInputState) -> UInt16 {
        var result: UInt16 = 0
        add(&result, XInputButton.a, ifPressed: input.buttons["a"])
        add(&result, XInputButton.b, ifPressed: input.buttons["b"])
        add(&result, XInputButton.x, ifPressed: input.buttons["x"])
        add(&result, XInputButton.y, ifPressed: input.buttons["y"])
        add(&result, XInputButton.back, ifPressed: input.buttons["view"])
        add(&result, XInputButton.start, ifPressed: input.buttons["menu"])
        add(&result, XInputButton.leftShoulder, ifPressed: input.buttons["left_shoulder"])
        add(&result, XInputButton.rightShoulder, ifPressed: input.buttons["right_shoulder"])
        add(&result, XInputButton.dpadUp, ifPressed: input.buttons["dpad_up"])
        add(&result, XInputButton.dpadDown, ifPressed: input.buttons["dpad_down"])
        add(&result, XInputButton.dpadLeft, ifPressed: input.buttons["dpad_left"])
        add(&result, XInputButton.dpadRight, ifPressed: input.buttons["dpad_right"])
        add(&result, XInputButton.leftThumb, ifPressed: input.buttons["left_stick_click"])
        add(&result, XInputButton.rightThumb, ifPressed: input.buttons["right_stick_click"])
        return result
    }

    private func add(_ buttons: inout UInt16, _ mask: UInt16, ifPressed value: Bool?) {
        if value == true {
            buttons |= mask
        }
    }

    private func trigger(from value: Int?) -> UInt8 {
        let raw = clamp(value ?? 0, min: 0, max: 32767)
        return UInt8((raw * 255) / 32767)
    }

    private func thumbAxis(from value: Int?) -> Int16 {
        Int16(clamping: clamp(value ?? 0, min: Int(Int16.min), max: Int(Int16.max)))
    }

    private func percent(from value: Int?) -> UInt8 {
        UInt8(clamping: clamp(value ?? 0, min: 0, max: 100))
    }

    private func voltage(from value: Int?) -> UInt16 {
        UInt16(clamping: clamp(value ?? 0, min: 0, max: Int(UInt16.max)))
    }

    private func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

