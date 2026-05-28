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
#define SCBR_PORT 26761
#define SCB1_PACKET_BYTES 26
#define SCBR_PACKET_BYTES 14
#define BATTERY_DEVTYPE_GAMEPAD 0x00
#define BATTERY_TYPE_DISCONNECTED 0x00
#define BATTERY_TYPE_ALKALINE 0x02
#define BATTERY_LEVEL_EMPTY 0x00
#define BATTERY_LEVEL_LOW 0x01
#define BATTERY_LEVEL_MEDIUM 0x02
#define BATTERY_LEVEL_FULL 0x03
#define XINPUT_GAMEPAD 0x01
#define XINPUT_CAPS_WIRELESS 0x0002

static const GUID SCB_NULL_GUID = {0, 0, 0, {0, 0, 0, 0, 0, 0, 0, 0}};

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
    WORD VirtualKey;
    WCHAR Unicode;
    WORD Flags;
    BYTE UserIndex;
    BYTE HidCode;
} XINPUT_KEYSTROKE_LOCAL;

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
static int bind_attempted = 0;
static DWORD rumble_packet = 1;

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

static void write_u16(unsigned char *data, int offset, uint16_t value) {
    data[offset] = (unsigned char)(value & 0x00ff);
    data[offset + 1] = (unsigned char)((value >> 8) & 0x00ff);
}

static void write_u32(unsigned char *data, int offset, uint32_t value) {
    data[offset] = (unsigned char)(value & 0x000000ff);
    data[offset + 1] = (unsigned char)((value >> 8) & 0x000000ff);
    data[offset + 2] = (unsigned char)((value >> 16) & 0x000000ff);
    data[offset + 3] = (unsigned char)((value >> 24) & 0x000000ff);
}

static void bridge_init(void) {
    if (bridge_socket != INVALID_SOCKET || bind_attempted) {
        return;
    }
    bind_attempted = 1;

    WSADATA data;
    if (WSAStartup(MAKEWORD(2, 2), &data) == 0) {
        winsock_ready = 1;
    }

    bridge_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (bridge_socket == INVALID_SOCKET) {
        return;
    }

    BOOL reuse = TRUE;
    setsockopt(bridge_socket, SOL_SOCKET, SO_REUSEADDR, (const char *)&reuse, sizeof(reuse));

    u_long nonblocking = 1;
    ioctlsocket(bridge_socket, FIONBIO, &nonblocking);

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(SCB1_PORT);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(bridge_socket, (struct sockaddr *)&address, sizeof(address)) != 0) {
        closesocket(bridge_socket);
        bridge_socket = INVALID_SOCKET;
    }
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
    pCapabilities->Gamepad.wButtons = 0xffff;
    pCapabilities->Gamepad.bLeftTrigger = 0xff;
    pCapabilities->Gamepad.bRightTrigger = 0xff;
    pCapabilities->Gamepad.sThumbLX = 0x7fff;
    pCapabilities->Gamepad.sThumbLY = 0x7fff;
    pCapabilities->Gamepad.sThumbRX = 0x7fff;
    pCapabilities->Gamepad.sThumbRY = 0x7fff;
    pCapabilities->Vibration.wLeftMotorSpeed = 0xffff;
    pCapabilities->Vibration.wRightMotorSpeed = 0xffff;
    return ERROR_SUCCESS;
}

DWORD WINAPI XInputGetCapabilitiesEx(
    DWORD reserved,
    DWORD dwUserIndex,
    DWORD dwFlags,
    XINPUT_CAPABILITIES_LOCAL *pCapabilities
) {
    (void)reserved;
    return XInputGetCapabilities(dwUserIndex, dwFlags, pCapabilities);
}

DWORD WINAPI XInputSetState(DWORD dwUserIndex, XINPUT_VIBRATION_LOCAL *pVibration) {
    bridge_poll();
    if (dwUserIndex != 0 || !bridge_state.connected || pVibration == NULL) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    unsigned char data[SCBR_PACKET_BYTES];
    data[0] = 'S';
    data[1] = 'C';
    data[2] = 'B';
    data[3] = 'R';
    data[4] = 1;
    data[5] = (unsigned char)dwUserIndex;
    write_u32(data, 6, rumble_packet++);
    write_u16(data, 10, pVibration->wLeftMotorSpeed);
    write_u16(data, 12, pVibration->wRightMotorSpeed);

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(SCBR_PORT);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sendto(bridge_socket, (const char *)data, sizeof(data), 0, (struct sockaddr *)&address, sizeof(address));

    return ERROR_SUCCESS;
}

DWORD WINAPI XInputGetDSoundAudioDeviceGuids(
    DWORD dwUserIndex,
    GUID *pDSoundRenderGuid,
    GUID *pDSoundCaptureGuid
) {
    bridge_poll();

    if (dwUserIndex != 0 || !bridge_state.connected) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    if (pDSoundRenderGuid != NULL) {
        *pDSoundRenderGuid = SCB_NULL_GUID;
    }

    if (pDSoundCaptureGuid != NULL) {
        *pDSoundCaptureGuid = SCB_NULL_GUID;
    }

    return ERROR_SUCCESS;
}

DWORD WINAPI XInputGetAudioDeviceIds(
    DWORD dwUserIndex,
    WCHAR *pRenderDeviceId,
    UINT *pRenderCount,
    WCHAR *pCaptureDeviceId,
    UINT *pCaptureCount
) {
    bridge_poll();

    if (dwUserIndex != 0 || !bridge_state.connected) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    if (pRenderCount != NULL) {
        *pRenderCount = 0;
    }

    if (pCaptureCount != NULL) {
        *pCaptureCount = 0;
    }

    if (pRenderDeviceId != NULL) {
        pRenderDeviceId[0] = L'\0';
    }

    if (pCaptureDeviceId != NULL) {
        pCaptureDeviceId[0] = L'\0';
    }

    return ERROR_SUCCESS;
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

DWORD WINAPI XInputGetKeystroke(DWORD dwUserIndex, DWORD dwReserved, XINPUT_KEYSTROKE_LOCAL *pKeystroke) {
    (void)dwReserved;
    bridge_poll();

    if (dwUserIndex != 0 || !bridge_state.connected) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    if (pKeystroke != NULL) {
        memset(pKeystroke, 0, sizeof(*pKeystroke));
    }

    return ERROR_EMPTY;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)instance;
    (void)reserved;

    if (reason == DLL_PROCESS_DETACH) {
        bridge_shutdown();
    }

    return TRUE;
}
