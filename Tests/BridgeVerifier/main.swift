import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let input = ControllerInputState(
    axes: [
        "left_trigger": 32767,
        "right_trigger": 16383,
        "left_stick_x": -32768,
        "left_stick_y": 32767,
        "right_stick_x": 1234,
        "right_stick_y": -4321,
        "battery_level": 78,
        "battery_voltage_mv": 2875
    ],
    buttons: [
        "a": true,
        "b": true,
        "x": true,
        "y": true,
        "view": true,
        "menu": true,
        "left_shoulder": true,
        "right_shoulder": true,
        "dpad_up": true,
        "dpad_down": false,
        "dpad_left": true,
        "dpad_right": false
    ]
)

let device = SteamControllerDevice(
    device_id: "test",
    name: "Steam Controller",
    product_id: 0x1142,
    is_connected: true,
    last_input_at: nil,
    battery_level: 78,
    battery_voltage: 2875,
    charge_state: nil,
    wireless_state: 2,
    input_state: input
)

let mapper = SteamToXInputMapper()
let mapped = mapper.map(device: device, packetNumber: 42)

expect(mapped.isConnected, "connected state maps through")
expect(mapped.packetNumber == 42, "packet number maps through")
expect(mapped.buttons & XInputButton.a != 0, "A maps")
expect(mapped.buttons & XInputButton.b != 0, "B maps")
expect(mapped.buttons & XInputButton.x != 0, "X maps")
expect(mapped.buttons & XInputButton.y != 0, "Y maps")
expect(mapped.buttons & XInputButton.back != 0, "view maps to back")
expect(mapped.buttons & XInputButton.start != 0, "menu maps to start")
expect(mapped.buttons & XInputButton.leftShoulder != 0, "left shoulder maps")
expect(mapped.buttons & XInputButton.rightShoulder != 0, "right shoulder maps")
expect(mapped.buttons & XInputButton.dpadUp != 0, "dpad up maps")
expect(mapped.buttons & XInputButton.dpadLeft != 0, "dpad left maps")
expect(mapped.buttons & XInputButton.dpadDown == 0, "dpad down remains clear")
expect(mapped.leftTrigger == 255, "left trigger scales to 255")
expect(mapped.rightTrigger == 127, "right trigger scales to midpoint")
expect(mapped.leftThumbX == Int16.min, "left X maps")
expect(mapped.leftThumbY == Int16.max, "left Y maps")
expect(mapped.rightThumbX == 1234, "right X maps")
expect(mapped.rightThumbY == -4321, "right Y maps")
expect(mapped.batteryPercent == 78, "battery percent maps")
expect(mapped.batteryVoltage == 2875, "battery voltage maps")

let encoded = SCB1PacketCodec.encode(mapped)
expect(encoded.count == SCB1PacketCodec.byteCount, "SCB1 packet length is stable")
expect(Array(encoded.prefix(4)) == [0x53, 0x43, 0x42, 0x31], "SCB1 magic is present")

let decoded = SCB1PacketCodec.decode(encoded)
expect(decoded == mapped, "SCB1 packet round-trips")

let disconnected = mapper.map(controllerState: .notConnected, packetNumber: 7)
expect(!disconnected.isConnected, "disconnected state maps")
expect(disconnected.packetNumber == 7, "disconnected packet number maps")

print("Bridge verifier passed")

