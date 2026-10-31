# Remote PC Controller System - System Architecture & Technical Specification

## Executive Summary
The Remote PC Controller System is a secure, cross-platform remote desktop management solution composed of an Android mobile application built with Flutter/Dart and a native Windows Companion PC Agent built with C#/.NET 8 (WPF).

The system supports real-time mouse/keyboard control, live screen streaming, system monitoring, process management, power management, and bidirectional file transfer across four communication layers:
1. Bluetooth Classic (RFCOMM/SPP)
2. Local Network (Wi-Fi)
3. Direct Mobile Hotspot Network
4. Internet Remote Connection (Firebase & WebRTC)

---

## 1. High-Level Architecture Diagram

```
+------------------------------------------------------------------------------------+
|                                FLUTTER ANDROID APP                                 |
|                                                                                    |
|  [ Presentation Layer ]  Dashboard | Touchpad | Keyboard | ScreenShare | FileMgr    |
|  [ Domain Layer ]        ConnectionUseCase | AuthUseCase | StreamUseCase           |
|  [ Data Layer ]          BluetoothRepo | LocalNetworkRepo | WebRTCRepo | SQLite    |
+------------------------------------------------------------------------------------+
                                      |   |   |
         +----------------------------+   |   +---------------------------+
         | Bluetooth Classic              | WebSocket over TLS (WSS)      | WebRTC Data/Media
         | RFCOMM Sockets                 | Local Network / Hotspot       | STUN/TURN Signaling
         v                                v                               v
+------------------------------------------------------------------------------------+
|                               WINDOWS C# PC AGENT                                  |
|                                                                                    |
|  [ Network Layer ]    BluetoothManager | LocalNetworkManager | WebRTCManager       |
|  [ Security Layer ]   AuthenticationManager | PairingManager | SecurityManager    |
|  [ Controller Layer ] MouseController | KeyboardController | AudioController      |
|  [ Subsystem Layer ]  ScreenCapture | ProcessManager | SystemMonitor | FileManager |
+------------------------------------------------------------------------------------+
```

---

## 2. Connection Modes & Transport Characteristics

| Connection Mode | Transport Layer | Data Channel | Live Screen Stream | File Transfer | Internet Required? | Setup / Pairing Method |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Bluetooth** | RFCOMM / SPP | Serial Sockets | ❌ Disabled | ⚠️ Low speed (<3MB) | ❌ No | System Bluetooth Pairing |
| **Local Wi-Fi** | WebSocket over TLS | TCP Socket (WSS) | ✅ WebRTC / H.264 | ✅ High speed | ❌ No | QR Code / PIN |
| **Mobile Hotspot**| WebSocket over TLS | TCP Socket (WSS) | ✅ WebRTC / H.264 | ✅ High speed | ❌ No | QR Code / PIN |
| **Internet** | WebRTC DataChannel | SCTP Protocol | ✅ WebRTC / H.264 | ✅ Chunked Stream | ✅ Yes | Firebase Auth + QR |

---

## 3. Communication Protocol Specification

All communication streams serialize messages using a standardized JSON frame envelope:

```json
{
  "version": 1,
  "msgId": "f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
  "type": "MOUSE_EVENT",
  "timestamp": 1710000000000,
  "payload": {
    "action": "MOVE",
    "dx": 12,
    "dy": -5,
    "button": "NONE"
  }
}
```

### Event Payload Specs:
- **MOUSE_EVENT**: Relative deltas (`dx`, `dy`), normalized touch coordinates (`absoluteX`, `absoluteY`), buttons (`LEFT`, `RIGHT`, `MIDDLE`), scroll deltas.
- **KEYBOARD_EVENT**: Virtual-Key codes, key actions (`KEY_DOWN`, `KEY_UP`), string input, modifiers (`CTRL`, `ALT`, `SHIFT`, `WIN`).
- **POWER_CMD**: Actions (`SHUTDOWN`, `RESTART`, `LOCK`, `SLEEP`).
- **VOLUME_CMD**: Actions (`SET_VOLUME`, `MUTE`, `UNMUTE`), level (`0.0 - 1.0`).
- **FILE_TRANSFER**: Chunk index, total chunks, base64 payload, SHA-256 checksum validation.
- **SYSTEM_METRICS**: CPU usage %, RAM used/total, Disk usage, Battery status, Network I/O.

---

## 4. Security & Access Control Model

1. **Zero Silent Access**: The Windows PC Agent runs strictly in the logged-in user's interactive session. An explicit System Tray icon and status indicator remain visible at all times.
2. **Mutual Pairing & QR Pinning**:
   - The Windows Agent displays a dynamic QR code containing:
     - Local IP & Port (`192.168.x.x:8443`)
     - One-time Pairing Token (256-bit entropy)
     - SHA-256 TLS Self-Signed Certificate Fingerprint (for TLS Pinning).
   - Android App scans the QR code and sends a signed handshake request.
3. **Encrypted Transports**:
   - Local LAN / Hotspot: WebSocket over TLS 1.3 (WSS) with Certificate Pinning.
   - Internet: DTLS 1.2 / SRTP for WebRTC media & SCTP WebRTC DataChannels.
4. **Command Whitelisting & Shell Guard**:
   - The Windows Agent executes inputs via explicit Windows API calls (`SendInput`, `CoreAudio`, `Windows Graphics Capture`).
   - Shell string commands, PowerShell execution, and arbitrary code execution are strictly prohibited.

---

## 5. C# Windows PC Agent Module Design

The Windows Agent application is structured into isolated, testable modules:

1. **`ConnectionManager`**: Unified supervisor managing state transitions across Bluetooth, Local Network, and WebRTC transports.
2. **`BluetoothManager`**: Handles 32feet.NET RFCOMM socket listener, pairing state, and packet parsing over Bluetooth.
3. **`LocalNetworkManager` & `WebSocketServer`**: Listens for incoming WSS client connections on local IP interfaces and Mobile Hotspot network interfaces (`192.168.43.x`).
4. **`WebRTCManager`**: Manages WebRTC peer connections, SDP offer/answer exchanges, ICE candidate gathering, and SCTP DataChannels.
5. **`MouseController` & `KeyboardController`**: Converts incoming input protocol packets into native Win32 `SendInput` p/invoke calls.
6. **`ScreenCapture` & `StreamingManager`**: Utilizes `Windows.Graphics.Capture` DirectX 11 API to capture desktop frames at 60 FPS and pipe them into H.264/VP8 WebRTC video encoders.
7. **`AudioController`**: Wraps Windows CoreAudio MMDevice APIs (`IAudioEndpointVolume`) for precision volume level and mute toggling.
8. **`FileManager`**: Provides secure directory enumeration, file chunking, streaming, and SHA-256 integrity verification.
9. **`ProcessManager`**: Interfaces with `System.Diagnostics.Process` to list active windows, launch approved programs, and terminate tasks.
10. **`SystemMonitor`**: Polls system performance counters (`PerformanceCounter`) for CPU, RAM, Disk activity, and battery status.
11. **`PowerManager`**: Executes Windows power state changes (`ExitWindowsEx`, `LockWorkStation`, `InitiateSystemShutdown`).
12. **`SecurityManager`**: Enforces QR token validation, rate-limiting, session expiration, and audit logging.

---

## 6. Development Roadmap (12 Phases)

- **Phase 1**: Project initialization, technical architecture, and folder setup. *(Current)*
- **Phase 2**: Windows Agent core WPF application, tray UI, and modular skeleton.
- **Phase 3**: Android-to-PC pairing and LAN WebSocket/TLS communication.
- **Phase 4**: Mouse and keyboard control (`SendInput` & Flutter touchpad UI).
- **Phase 5**: Live screen sharing (`Windows Graphics Capture` & Flutter WebRTC viewer).
- **Phase 6**: Shutdown, restart, lock, and audio volume controls.
- **Phase 7**: Process manager and real-time system monitoring.
- **Phase 8**: Bidirectional file transfer with progress tracking.
- **Phase 9**: Bluetooth Classic RFCOMM channel implementation.
- **Phase 10**: Firebase authentication and Internet remote connection.
- **Phase 11**: Automatic connection manager, mode fallback, and auto-reconnect logic.
- **Phase 12**: Security auditing, performance optimization, and deployment packaging (APK & Windows Installer).
