import Foundation

struct XInputControllerState: Equatable {
    var isConnected: Bool
    var packetNumber: UInt32
    var buttons: UInt16
    var leftTrigger: UInt8
    var rightTrigger: UInt8
    var leftThumbX: Int16
    var leftThumbY: Int16
    var rightThumbX: Int16
    var rightThumbY: Int16
    var batteryPercent: UInt8
    var batteryVoltage: UInt16

    static let disconnected = XInputControllerState(
        isConnected: false,
        packetNumber: 0,
        buttons: 0,
        leftTrigger: 0,
        rightTrigger: 0,
        leftThumbX: 0,
        leftThumbY: 0,
        rightThumbX: 0,
        rightThumbY: 0,
        batteryPercent: 0,
        batteryVoltage: 0
    )
}

enum XInputButton {
    static let dpadUp: UInt16 = 0x0001
    static let dpadDown: UInt16 = 0x0002
    static let dpadLeft: UInt16 = 0x0004
    static let dpadRight: UInt16 = 0x0008
    static let start: UInt16 = 0x0010
    static let back: UInt16 = 0x0020
    static let leftThumb: UInt16 = 0x0040
    static let rightThumb: UInt16 = 0x0080
    static let leftShoulder: UInt16 = 0x0100
    static let rightShoulder: UInt16 = 0x0200
    static let a: UInt16 = 0x1000
    static let b: UInt16 = 0x2000
    static let x: UInt16 = 0x4000
    static let y: UInt16 = 0x8000
}

