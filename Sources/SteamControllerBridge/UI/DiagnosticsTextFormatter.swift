import Foundation

struct DiagnosticsTextFormatter {
    func devicesText(puckStates: [PuckState], controllerState: ControllerConnectionState) -> String {
        var lines: [String] = []

        lines.append("Pucks")
        if puckStates.isEmpty {
            lines.append("  not detected")
        } else {
            for (index, puck) in puckStates.enumerated() {
                lines.append("  \(index + 1). \(puck.product_name ?? "Steam Controller puck")")
                lines.append("     PID: \(productIDTitle(for: puck))")
                lines.append("     Transport: \(puck.transport ?? "unknown")")
                lines.append("     Location: \(hexTitle(puck.location_id, width: 8))")
            }
        }

        lines.append("")
        lines.append("Controllers")
        let connectedControllers = controllerState.connectedDevices
        if connectedControllers.isEmpty {
            lines.append("  not connected")
        } else {
            for (index, controller) in connectedControllers.enumerated() {
                lines.append("  \(index + 1). \(controller.name)")
                lines.append("     ID: \(controller.device_id)")
                lines.append("     Battery: \(batteryTitle(controller))")
                lines.append("     Wireless: \(wirelessTitle(controller))")
                lines.append("     Last input: \(lastInputTitle(controller.last_input_at))")
            }
        }

        return lines.joined(separator: "\n")
    }

    func inputText(controllerState: ControllerConnectionState) -> String {
        let connectedControllers = controllerState.connectedDevices
        guard !connectedControllers.isEmpty else {
            return "Controller: not connected"
        }

        var lines: [String] = []
        for (index, controller) in connectedControllers.enumerated() {
            if index > 0 {
                lines.append("")
            }

            lines.append(controller.name)
            lines.append("Battery: \(batteryTitle(controller))")
            lines.append("Wireless: \(wirelessTitle(controller))")
            lines.append("")
            lines.append("Axes")
            for key in controller.input_state.axes.keys.sorted() {
                lines.append("  \(key): \(controller.input_state.axes[key] ?? 0)")
            }

            lines.append("")
            lines.append("Buttons")
            for key in controller.input_state.buttons.keys.sorted() {
                lines.append("  \(key): \(pressedTitle(controller.input_state.buttons[key] ?? false))")
            }
        }

        return lines.joined(separator: "\n")
    }

    func bridgeText(
        controllerState: ControllerConnectionState,
        bridgeStatus: LocalBridgeStatus,
        installStatus: WineBridgeInstallStatus
    ) -> String {
        let xinputState = SteamToXInputMapper().map(
            controllerState: controllerState,
            packetNumber: bridgeStatus.lastState.packetNumber
        )

        var lines: [String] = []
        lines.append("Local UDP Bridge")
        lines.append("  Protocol: SCB1")
        lines.append("  Address: 127.0.0.1:\(bridgeStatus.port)")
        lines.append("  Packets sent: \(bridgeStatus.packetCount)")
        lines.append("  Last send: \(lastSendTitle(bridgeStatus.lastSendAt))")
        lines.append("  Status: \(bridgeStatus.lastError ?? "sending")")
        lines.append("")

        lines.append("Translated XInput")
        appendXInputState(xinputState, to: &lines)
        lines.append("")

        lines.append("Last Sent Packet")
        appendXInputState(bridgeStatus.lastState, to: &lines)
        lines.append("")

        lines.append("Wine Bridge Install")
        lines.append("  Prefix: \(installStatus.selectedPrefixPath ?? "not selected")")
        lines.append("  Status: \(installStatus.message)")

        return lines.joined(separator: "\n")
    }

    private func productIDTitle(for state: PuckState) -> String {
        guard let productID = state.product_id else { return "unknown" }

        let formatted = hexTitle(productID, width: 4)
        if state.is_legacy {
            return "\(formatted) legacy"
        }

        return formatted
    }

    private func hexTitle(_ value: Int?, width: Int) -> String {
        guard let value else { return "unknown" }
        return String(format: "0x%0\(width)x", value)
    }

    private func pressedTitle(_ value: Bool) -> String {
        value ? "down" : "-"
    }

    private func batteryTitle(_ controller: SteamControllerDevice) -> String {
        let level = controller.battery_level.map { "\($0)%" } ?? "unknown"
        let voltage = controller.battery_voltage.map { "\($0) mV" } ?? nil
        return [level, voltage].compactMap { $0 }.joined(separator: ", ")
    }

    private func wirelessTitle(_ controller: SteamControllerDevice) -> String {
        guard let state = controller.wireless_state else {
            return controller.is_connected ? "connected" : "unknown"
        }

        switch state {
        case 1:
            return "disconnected (state 1)"
        case 2:
            return "connected (state 2)"
        default:
            return "state \(state)"
        }
    }

    private func lastInputTitle(_ date: Date?) -> String {
        guard let date else { return "none" }
        let seconds = max(0, Date().timeIntervalSince(date))
        return String(format: "%.1fs ago", seconds)
    }

    private func lastSendTitle(_ date: Date?) -> String {
        guard let date else { return "never" }
        let seconds = max(0, Date().timeIntervalSince(date))
        return String(format: "%.2fs ago", seconds)
    }

    private func appendXInputState(_ state: XInputControllerState, to lines: inout [String]) {
        lines.append("  Connected: \(state.isConnected ? "yes" : "no")")
        lines.append("  Packet: \(state.packetNumber)")
        lines.append("  Buttons: \(String(format: "0x%04x", state.buttons))")
        lines.append("  Triggers: L \(state.leftTrigger), R \(state.rightTrigger)")
        lines.append("  Left thumb: \(state.leftThumbX), \(state.leftThumbY)")
        lines.append("  Right thumb: \(state.rightThumbX), \(state.rightThumbY)")
        lines.append("  Battery: \(state.batteryPercent)%, \(state.batteryVoltage) mV")
    }
}
