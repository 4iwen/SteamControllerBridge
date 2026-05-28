import Foundation

struct ControllerConnectionState: Equatable {
    var devices: [SteamControllerDevice]

    var connectedDevices: [SteamControllerDevice] {
        devices.filter { $0.is_connected }
    }

    var controller_is_connected: Bool {
        !connectedDevices.isEmpty
    }

    var controller_name: String? {
        devices.first(where: { $0.is_connected })?.name ?? devices.first?.name
    }

    var controller_path_or_id: String? {
        devices.first(where: { $0.is_connected })?.device_id ?? devices.first?.device_id
    }

    var input_state: ControllerInputState {
        devices.first(where: { $0.is_connected })?.input_state ?? devices.first?.input_state ?? .empty
    }

    static let notConnected = ControllerConnectionState(
        devices: []
    )
}

struct SteamControllerDevice: Equatable {
    var device_id: String
    var name: String
    var product_id: Int?
    var is_connected: Bool
    var last_input_at: Date?
    var battery_level: Int?
    var battery_voltage: Int?
    var charge_state: Int?
    var wireless_state: Int?
    var input_state: ControllerInputState
}
