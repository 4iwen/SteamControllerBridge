struct ControllerConnectionState: Equatable {
    var controller_is_connected: Bool
    var controller_name: String?
    var controller_path_or_id: String?
    var sdl_gamepad_count: Int

    static let notConnected = ControllerConnectionState(
        controller_is_connected: false,
        controller_name: nil,
        controller_path_or_id: nil,
        sdl_gamepad_count: 0
    )
}
