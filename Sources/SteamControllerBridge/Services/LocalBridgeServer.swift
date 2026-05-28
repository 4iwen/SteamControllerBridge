import Darwin
import Foundation

struct LocalBridgeStatus: Equatable {
    var port: UInt16
    var rumblePort: UInt16
    var packetCount: UInt64
    var lastSendAt: Date?
    var lastError: String?
    var lastState: XInputControllerState
    var lastRumble: RumbleCommand?

    static let initial = LocalBridgeStatus(
        port: SCB1PacketCodec.port,
        rumblePort: RumbleCommandCodec.port,
        packetCount: 0,
        lastSendAt: nil,
        lastError: nil,
        lastState: .disconnected,
        lastRumble: nil
    )
}

struct RumbleCommand: Equatable {
    var packetNumber: UInt32
    var leftMotor: UInt16
    var rightMotor: UInt16
    var receivedAt: Date
}

enum RumbleCommandCodec {
    static let port: UInt16 = 26761
    static let byteCount = 14

    static func decode(_ bytes: [UInt8]) -> RumbleCommand? {
        guard bytes.count >= byteCount,
              bytes[0] == 0x53,
              bytes[1] == 0x43,
              bytes[2] == 0x42,
              bytes[3] == 0x52,
              bytes[4] == 1 else {
            return nil
        }

        return RumbleCommand(
            packetNumber: UInt32(bytes[6])
                | (UInt32(bytes[7]) << 8)
                | (UInt32(bytes[8]) << 16)
                | (UInt32(bytes[9]) << 24),
            leftMotor: UInt16(bytes[10]) | (UInt16(bytes[11]) << 8),
            rightMotor: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8),
            receivedAt: Date()
        )
    }
}

final class LocalBridgeServer {
    var onStatusChange: ((LocalBridgeStatus) -> Void)?
    var onRumbleCommand: ((RumbleCommand) -> Void)?

    private let mapper = SteamToXInputMapper()
    private let keepaliveInterval: TimeInterval = 0.25
    private var socketFD: Int32 = -1
    private var rumbleSocketFD: Int32 = -1
    private var address = sockaddr_in()
    private var timer: DispatchSourceTimer?
    private var rumbleSource: DispatchSourceRead?
    private var lastPublishedControllerState = ControllerConnectionState.notConnected
    private var lastSentComparableState: XInputControllerState?
    private var nextPacketNumber: UInt32 = 1
    private(set) var status = LocalBridgeStatus.initial

    deinit {
        stop()
    }

    func start() {
        guard socketFD < 0 else { return }

        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if socketFD < 0 {
            updateStatus(error: errnoTitle("socket"))
            return
        }

        address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: SCB1PacketCodec.port.bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: keepaliveInterval)
        source.setEventHandler { [weak self] in
            self?.sendCurrentState(force: true)
        }
        source.resume()
        timer = source

        startRumbleReceiver()
    }

    func stop() {
        timer?.cancel()
        timer = nil

        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }

        rumbleSource?.cancel()
        rumbleSource = nil

        if rumbleSocketFD >= 0 {
            close(rumbleSocketFD)
            rumbleSocketFD = -1
        }
    }

    func update(controllerState: ControllerConnectionState) {
        lastPublishedControllerState = controllerState
        sendCurrentState(force: false)
    }

    private func sendCurrentState(force: Bool) {
        var mapped = mapper.map(controllerState: lastPublishedControllerState, packetNumber: nextPacketNumber)
        let comparable = comparableState(mapped)

        guard force || comparable != lastSentComparableState else {
            return
        }

        mapped.packetNumber = nextPacketNumber
        send(mapped)
        lastSentComparableState = comparable
        nextPacketNumber &+= 1
    }

    private func send(_ state: XInputControllerState) {
        guard socketFD >= 0 else {
            updateStatus(error: "UDP socket is not open")
            return
        }

        let data = SCB1PacketCodec.encode(state)
        let sent = data.withUnsafeBytes { rawBuffer -> ssize_t in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            var target = address
            return withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(socketFD, baseAddress, data.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        if sent == data.count {
            status.packetCount += 1
            status.lastSendAt = Date()
            status.lastError = nil
            status.lastState = state
        } else {
            status.lastError = errnoTitle("sendto")
        }

        publishStatus()
    }

    private func comparableState(_ state: XInputControllerState) -> XInputControllerState {
        var copy = state
        copy.packetNumber = 0
        return copy
    }

    private func updateStatus(error: String?) {
        status.lastError = error
        publishStatus()
    }

    private func publishStatus() {
        onStatusChange?(status)
    }

    private func startRumbleReceiver() {
        rumbleSocketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard rumbleSocketFD >= 0 else {
            updateStatus(error: errnoTitle("rumble socket"))
            return
        }

        var reuse: Int32 = 1
        setsockopt(rumbleSocketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var localAddress = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: RumbleCommandCodec.port.bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindResult = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(rumbleSocketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            updateStatus(error: errnoTitle("rumble bind"))
            close(rumbleSocketFD)
            rumbleSocketFD = -1
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: rumbleSocketFD, queue: .main)
        source.setEventHandler { [weak self] in
            self?.receiveRumbleCommands()
        }
        source.resume()
        rumbleSource = source
    }

    private func receiveRumbleCommands() {
        var buffer = [UInt8](repeating: 0, count: 64)
        while true {
            let received = recv(rumbleSocketFD, &buffer, buffer.count, MSG_DONTWAIT)
            guard received > 0 else { return }
            guard let command = RumbleCommandCodec.decode(Array(buffer.prefix(received))) else { continue }
            status.lastRumble = command
            onRumbleCommand?(command)
            publishStatus()
        }
    }

    private func errnoTitle(_ operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }
}
