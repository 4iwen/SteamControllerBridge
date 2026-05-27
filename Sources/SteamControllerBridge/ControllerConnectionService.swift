import Foundation
import CSDL3

final class ControllerConnectionService {
    var onStateChange: ((ControllerConnectionState) -> Void)?

    private var state = ControllerConnectionState.notConnected
    private var gamepad: OpaquePointer?
    private var timer: Timer?
    private var initializedSDL = false

    deinit {
        timer?.invalidate()

        if let gamepad {
            SDL_CloseGamepad(gamepad)
        }

        if initializedSDL {
            SDL_QuitSubSystem(SDL_INIT_GAMEPAD)
        }
    }

    func start() {
        guard !initializedSDL else { return }

        guard SDL_InitSubSystem(SDL_INIT_GAMEPAD) else {
            publish(.notConnected)
            return
        }

        initializedSDL = true
        refreshState()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard initializedSDL else { return }

        var event = SDL_Event()
        while SDL_PollEvent(&event) {
            switch SDL_EventType(event.type) {
            case SDL_EVENT_GAMEPAD_ADDED,
                 SDL_EVENT_GAMEPAD_REMOVED,
                 SDL_EVENT_GAMEPAD_REMAPPED,
                 SDL_EVENT_GAMEPAD_UPDATE_COMPLETE,
                 SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED:
                break
            default:
                break
            }
        }

        refreshState()
    }

    private func refreshState() {
        guard initializedSDL else {
            publish(.notConnected)
            return
        }

        var count: Int32 = 0
        guard let gamepadIDs = SDL_GetGamepads(&count), count > 0 else {
            if let gamepad {
                SDL_CloseGamepad(gamepad)
                self.gamepad = nil
            }
            publish(ControllerConnectionState(
                controller_is_connected: false,
                controller_name: nil,
                controller_path_or_id: nil,
                sdl_gamepad_count: Int(max(count, 0))
            ))
            return
        }

        defer { SDL_free(gamepadIDs) }

        let firstID = gamepadIDs[0]
        if let current = gamepad, SDL_GamepadConnected(current), SDL_GetGamepadID(current) == firstID {
            publish(state(for: current, count: Int(count), fallbackID: firstID))
            return
        }

        if let gamepad {
            SDL_CloseGamepad(gamepad)
            self.gamepad = nil
        }

        guard let opened = SDL_OpenGamepad(firstID) else {
            publish(ControllerConnectionState(
                controller_is_connected: false,
                controller_name: cString(SDL_GetGamepadNameForID(firstID)),
                controller_path_or_id: pathOrID(path: cString(SDL_GetGamepadPathForID(firstID)), id: firstID),
                sdl_gamepad_count: Int(count)
            ))
            return
        }

        gamepad = opened
        publish(state(for: opened, count: Int(count), fallbackID: firstID))
    }

    private func state(for gamepad: OpaquePointer, count: Int, fallbackID: SDL_JoystickID) -> ControllerConnectionState {
        ControllerConnectionState(
            controller_is_connected: SDL_GamepadConnected(gamepad),
            controller_name: cString(SDL_GetGamepadName(gamepad)),
            controller_path_or_id: pathOrID(path: cString(SDL_GetGamepadPath(gamepad)), id: fallbackID),
            sdl_gamepad_count: count
        )
    }

    private func publish(_ nextState: ControllerConnectionState) {
        guard nextState != state else { return }
        state = nextState
        DispatchQueue.main.async { [state, onStateChange] in
            onStateChange?(state)
        }
    }

    private func cString(_ pointer: UnsafePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(cString: pointer)
    }

    private func pathOrID(path: String?, id: SDL_JoystickID) -> String {
        if let path, !path.isEmpty {
            return path
        }

        return "SDL joystick id \(id)"
    }
}
