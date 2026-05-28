struct ControllerInputState: Equatable {
    var axes: [String: Int]
    var buttons: [String: Bool]

    static let empty = ControllerInputState(axes: [:], buttons: [:])
}
