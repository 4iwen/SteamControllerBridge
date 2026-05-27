import Foundation

struct ControllerConnectionState: Equatable {
    var devices: [SteamControllerDevice]

    var controller_is_connected: Bool {
        devices.contains { $0.is_connected }
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
    var is_connected: Bool
    var last_input_at: Date?
    var input_state: ControllerInputState
}
