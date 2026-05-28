import Darwin
import Foundation

@main
struct UDPReceiver {
    static func main() {
        let expectedPackets = Int(CommandLine.arguments.dropFirst().first ?? "1") ?? 1
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if fd < 0 {
            fputs("socket failed\n", stderr)
            exit(1)
        }

        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: SCB1PacketCodec.port.bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult != 0 {
            fputs("bind failed: \(String(cString: strerror(errno)))\n", stderr)
            exit(1)
        }

        var lastPacket: UInt32?
        for _ in 0..<expectedPackets {
            var buffer = [UInt8](repeating: 0, count: SCB1PacketCodec.byteCount)
            let received = recv(fd, &buffer, buffer.count, 0)
            if received != SCB1PacketCodec.byteCount {
                fputs("unexpected packet size \(received)\n", stderr)
                exit(1)
            }

            guard let state = SCB1PacketCodec.decode(Data(buffer)) else {
                fputs("invalid SCB1 packet\n", stderr)
                exit(1)
            }

            if let lastPacket {
                guard state.packetNumber > lastPacket else {
                    fputs("packet order regression: \(state.packetNumber) after \(lastPacket)\n", stderr)
                    exit(1)
                }
            }

            lastPacket = state.packetNumber
            print("packet=\(state.packetNumber) connected=\(state.isConnected) buttons=\(String(format: "0x%04x", state.buttons))")
        }

        close(fd)
    }
}
