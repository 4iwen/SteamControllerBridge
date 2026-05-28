import Darwin
import Foundation

struct LocalBridgeStatus: Equatable {
    var port: UInt16
    var packetCount: UInt64
    var lastSendAt: Date?
    var lastError: String?
    var lastState: XInputControllerState

    static let initial = LocalBridgeStatus(
        port: SCB1PacketCodec.port,
        packetCount: 0,
        lastSendAt: nil,
        lastError: nil,
        lastState: .disconnected
    )
}

final class LocalBridgeServer {
    var onStatusChange: ((LocalBridgeStatus) -> Void)?

    private let mapper = SteamToXInputMapper()
    private let keepaliveInterval: TimeInterval = 0.25
    private var socketFD: Int32 = -1
    private var address = sockaddr_in()
    private var timer: DispatchSourceTimer?
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
    }

    func stop() {
        timer?.cancel()
        timer = nil

        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
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

    private func errnoTitle(_ operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }
}

