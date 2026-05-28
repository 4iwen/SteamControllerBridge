import Foundation

enum SCB1PacketCodec {
    static let port: UInt16 = 26760
    static let byteCount = 26

    static func encode(_ state: XInputControllerState) -> Data {
        var data = Data()
        data.reserveCapacity(byteCount)

        data.append(contentsOf: [0x53, 0x43, 0x42, 0x31])
        data.append(1)
        data.append(state.isConnected ? 1 : 0)
        data.append(state.batteryPercent)
        data.append(0)
        appendUInt32(state.packetNumber, to: &data)
        appendUInt16(state.buttons, to: &data)
        data.append(state.leftTrigger)
        data.append(state.rightTrigger)
        appendInt16(state.leftThumbX, to: &data)
        appendInt16(state.leftThumbY, to: &data)
        appendInt16(state.rightThumbX, to: &data)
        appendInt16(state.rightThumbY, to: &data)
        appendUInt16(state.batteryVoltage, to: &data)

        return data
    }

    static func decode(_ data: Data) -> XInputControllerState? {
        guard data.count >= byteCount,
              data[0] == 0x53,
              data[1] == 0x43,
              data[2] == 0x42,
              data[3] == 0x31,
              data[4] == 1 else {
            return nil
        }

        return XInputControllerState(
            isConnected: data[5] != 0,
            packetNumber: readUInt32(data, offset: 8),
            buttons: readUInt16(data, offset: 12),
            leftTrigger: data[14],
            rightTrigger: data[15],
            leftThumbX: readInt16(data, offset: 16),
            leftThumbY: readInt16(data, offset: 18),
            rightThumbX: readInt16(data, offset: 20),
            rightThumbY: readInt16(data, offset: 22),
            batteryPercent: data[6],
            batteryVoltage: readUInt16(data, offset: 24)
        )
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00ff))
        data.append(UInt8((value >> 8) & 0x00ff))
    }

    private static func appendInt16(_ value: Int16, to data: inout Data) {
        appendUInt16(UInt16(bitPattern: value), to: &data)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x000000ff))
        data.append(UInt8((value >> 8) & 0x000000ff))
        data.append(UInt8((value >> 16) & 0x000000ff))
        data.append(UInt8((value >> 24) & 0x000000ff))
    }

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readInt16(_ data: Data, offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(data, offset: offset))
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

