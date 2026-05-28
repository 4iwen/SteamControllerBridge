struct StatusMenuFormatter {
    func title(puckStates: [PuckState], controllerState: ControllerConnectionState) -> String {
        let connectedControllers = controllerState.connectedDevices
        if !connectedControllers.isEmpty {
            let countTitle = connectedControllers.count == 1
                ? "1 controller"
                : "\(connectedControllers.count) controllers"
            return "\(countTitle), battery \(batterySummary(connectedControllers))"
        }

        if !puckStates.isEmpty {
            return puckStates.count == 1 ? "Puck connected" : "\(puckStates.count) pucks connected"
        }

        return "No puck detected"
    }

    private func batterySummary(_ devices: [SteamControllerDevice]) -> String {
        let values = devices.map { device -> String in
            device.battery_level.map { "\($0)%" } ?? "--"
        }

        return values.joined(separator: "/")
    }
}
