/*
 * SteamControllerBridge Wine XInput DLL.
 *
 * Build with MinGW-w64, then copy the resulting DLL to:
 *   xinput1_3.dll
 *   xinput1_4.dll
 *   xinput9_1_0.dll
 */
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>
#include <stdint.h>
#include <string.h>

#define SCB1_PORT 26760
#define SCB1_PACKET_BYTES 26
#define BATTERY_DEVTYPE_GAMEPAD 0x00
#define BATTERY_TYPE_DISCONNECTED 0x00
#define BATTERY_TYPE_ALKALINE 0x02
#define BATTERY_LEVEL_EMPTY 0x00
#define BATTERY_LEVEL_LOW 0x01
#define BATTERY_LEVEL_MEDIUM 0x02
#define BATTERY_LEVEL_FULL 0x03
#define XINPUT_GAMEPAD 0x01
#define XINPUT_CAPS_WIRELESS 0x0002

typedef struct {
    WORD wButtons;
    BYTE bLeftTrigger;
    BYTE bRightTrigger;
    SHORT sThumbLX;
    SHORT sThumbLY;
    SHORT sThumbRX;
    SHORT sThumbRY;
} XINPUT_GAMEPAD_LOCAL;

typedef struct {
    DWORD dwPacketNumber;
    XINPUT_GAMEPAD_LOCAL Gamepad;
} XINPUT_STATE_LOCAL;

typedef struct {
    BYTE Type;
    BYTE SubType;
    WORD Flags;
    XINPUT_GAMEPAD_LOCAL Gamepad;
    struct {
        WORD wLeftMotorSpeed;
        WORD wRightMotorSpeed;
    } Vibration;
} XINPUT_CAPABILITIES_LOCAL;

typedef struct {
    BYTE BatteryType;
    BYTE BatteryLevel;
} XINPUT_BATTERY_INFORMATION_LOCAL;

typedef struct {
    WORD wLeftMotorSpeed;
    WORD wRightMotorSpeed;
} XINPUT_VIBRATION_LOCAL;

typedef struct {
    int connected;
    DWORD packet;
    WORD buttons;
    BYTE left_trigger;
    BYTE right_trigger;
    SHORT left_x;
    SHORT left_y;
    SHORT right_x;
    SHORT right_y;
    BYTE battery_percent;
    WORD battery_mv;
    DWORD last_tick;
} BridgeState;

static SOCKET bridge_socket = INVALID_SOCKET;
static BridgeState bridge_state;
static int winsock_ready = 0;

static uint16_t read_u16(const unsigned char *data, int offset) {
    return (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
}

static int16_t read_i16(const unsigned char *data, int offset) {
    return (int16_t)read_u16(data, offset);
}

static uint32_t read_u32(const unsigned char *data, int offset) {
    return (uint32_t)data[offset]
        | ((uint32_t)data[offset + 1] << 8)
        | ((uint32_t)data[offset + 2] << 16)
        | ((uint32_t)data[offset + 3] << 24);
}

static void bridge_init(void) {
    if (bridge_socket != INVALID_SOCKET) {
        return;
    }

    WSADATA data;
    if (WSAStartup(MAKEWORD(2, 2), &data) == 0) {
        winsock_ready = 1;
    }

    bridge_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (bridge_socket == INVALID_SOCKET) {
        return;
    }

    u_long nonblocking = 1;
    ioctlsocket(bridge_socket, FIONBIO, &nonblocking);

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(SCB1_PORT);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(bridge_socket, (struct sockaddr *)&address, sizeof(address));
}

static void bridge_shutdown(void) {
    if (bridge_socket != INVALID_SOCKET) {
        closesocket(bridge_socket);
        bridge_socket = INVALID_SOCKET;
    }

    if (winsock_ready) {
        WSACleanup();
        winsock_ready = 0;
    }
}

static void bridge_poll(void) {
    bridge_init();
    if (bridge_socket == INVALID_SOCKET) {
        return;
    }

    unsigned char data[SCB1_PACKET_BYTES];
    for (;;) {
        int received = recv(bridge_socket, (char *)data, sizeof(data), 0);
        if (received < SCB1_PACKET_BYTES) {
            break;
        }

        if (data[0] != 'S' || data[1] != 'C' || data[2] != 'B' || data[3] != '1' || data[4] != 1) {
            continue;
        }

        bridge_state.connected = data[5] != 0;
        bridge_state.battery_percent = data[6];
        bridge_state.packet = read_u32(data, 8);
        bridge_state.buttons = read_u16(data, 12);
        bridge_state.left_trigger = data[14];
        bridge_state.right_trigger = data[15];
        bridge_state.left_x = read_i16(data, 16);
        bridge_state.left_y = read_i16(data, 18);
        bridge_state.right_x = read_i16(data, 20);
        bridge_state.right_y = read_i16(data, 22);
        bridge_state.battery_mv = read_u16(data, 24);
        bridge_state.last_tick = GetTickCount();
    }

    if (bridge_state.connected && GetTickCount() - bridge_state.last_tick > 1500) {
        bridge_state.connected = 0;
    }
}

DWORD WINAPI XInputGetState(DWORD dwUserIndex, XINPUT_STATE_LOCAL *pState) {
    bridge_poll();

    if (dwUserIndex != 0 || !bridge_state.connected || pState == NULL) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    memset(pState, 0, sizeof(*pState));
    pState->dwPacketNumber = bridge_state.packet;
    pState->Gamepad.wButtons = bridge_state.buttons;
    pState->Gamepad.bLeftTrigger = bridge_state.left_trigger;
    pState->Gamepad.bRightTrigger = bridge_state.right_trigger;
    pState->Gamepad.sThumbLX = bridge_state.left_x;
    pState->Gamepad.sThumbLY = bridge_state.left_y;
    pState->Gamepad.sThumbRX = bridge_state.right_x;
    pState->Gamepad.sThumbRY = bridge_state.right_y;
    return ERROR_SUCCESS;
}

DWORD WINAPI XInputGetCapabilities(DWORD dwUserIndex, DWORD dwFlags, XINPUT_CAPABILITIES_LOCAL *pCapabilities) {
    (void)dwFlags;
    bridge_poll();

    if (dwUserIndex != 0 || !bridge_state.connected || pCapabilities == NULL) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    memset(pCapabilities, 0, sizeof(*pCapabilities));
    pCapabilities->Type = XINPUT_GAMEPAD;
    pCapabilities->SubType = XINPUT_GAMEPAD;
    pCapabilities->Flags = XINPUT_CAPS_WIRELESS;
    return ERROR_SUCCESS;
}

DWORD WINAPI XInputSetState(DWORD dwUserIndex, XINPUT_VIBRATION_LOCAL *pVibration) {
    (void)pVibration;
    bridge_poll();
    return (dwUserIndex == 0 && bridge_state.connected) ? ERROR_SUCCESS : ERROR_DEVICE_NOT_CONNECTED;
}

void WINAPI XInputEnable(BOOL enable) {
    (void)enable;
}

DWORD WINAPI XInputGetBatteryInformation(
    DWORD dwUserIndex,
    BYTE devType,
    XINPUT_BATTERY_INFORMATION_LOCAL *pBatteryInformation
) {
    (void)devType;
    bridge_poll();

    if (dwUserIndex != 0 || !bridge_state.connected || pBatteryInformation == NULL) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    pBatteryInformation->BatteryType = BATTERY_TYPE_ALKALINE;
    if (bridge_state.battery_percent >= 70) {
        pBatteryInformation->BatteryLevel = BATTERY_LEVEL_FULL;
    } else if (bridge_state.battery_percent >= 35) {
        pBatteryInformation->BatteryLevel = BATTERY_LEVEL_MEDIUM;
    } else if (bridge_state.battery_percent > 0) {
        pBatteryInformation->BatteryLevel = BATTERY_LEVEL_LOW;
    } else {
        pBatteryInformation->BatteryLevel = BATTERY_LEVEL_EMPTY;
    }
    return ERROR_SUCCESS;
}

DWORD WINAPI XInputGetKeystroke(DWORD dwUserIndex, DWORD dwReserved, void *pKeystroke) {
    (void)dwReserved;
    (void)pKeystroke;
    bridge_poll();
    return (dwUserIndex == 0 && bridge_state.connected) ? ERROR_EMPTY : ERROR_DEVICE_NOT_CONNECTED;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)instance;
    (void)reserved;

    if (reason == DLL_PROCESS_ATTACH) {
        bridge_init();
    } else if (reason == DLL_PROCESS_DETACH) {
        bridge_shutdown();
    }

    return TRUE;
}
