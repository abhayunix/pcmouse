# PC Mouse & Remote Control System 🚀

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![.NET 8](https://img.shields.io/badge/.NET-8.0-512BD4?logo=dotnet)](https://dotnet.microsoft.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11%20%7C%20Android-blue)](#)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-quality, low-latency Remote PC Controller allowing users to manage a **Windows 10/11 PC** seamlessly from an **Android smartphone** via **Local Wi-Fi / Hotspot** and **Bluetooth RFCOMM**.

---

## 🌟 Features Showcase

### 🖱️ 1. Windows 11 Precision Touchpad & Multi-Touch Gestures
- **Ballistic Smooth Cursor Tracking**: Powered by sub-pixel fraction accumulation and Windows 11 non-linear velocity acceleration curves for ultra-smooth 60/120 Hz cursor gliding.
- **Multi-Touch Gestures**:
  - **1-Finger Tap**: Left Click
  - **2-Finger Tap / Double Tap**: Right Click
  - **2-Finger Sliding**: 2D Smooth Scrolling (Up, Down, Left, Right)
  - **2-Finger Pinch**: Zoom In / Zoom Out (`Ctrl + Scroll`)
  - **3-Finger Swipe Up**: Open Windows Task View (`Win + Tab`)
  - **3-Finger Swipe Down**: Minimize All / Show Desktop (`Win + D`)
  - **3-Finger Swipe Left / Right**: Switch Active Applications (`Alt + Tab`)
- **Drag-Select Mode (✋)**: Toggle Mouse Left Button Hold to drag windows or select text across PC screens.
- **Widescreen Landscape Mode (🔄)**: Rotates the phone horizontally into a vast, widescreen trackpad matching 16:9 PC displays.
- **Immersive Full-Screen Mode (⛶)**: Hides status bars for an uninterrupted 100% full-screen glass trackpad experience.
- **4-Way Directional Scroll D-Pad**: Compact floating 2-row scroll box (Row 1: Up ▲ | Row 2: Left ◄, Down ▼, Right ►) for continuous press-and-hold page scrolling.

### ⌨️ 2. Live Phone Keyboard & Quick Shortcuts
- **Live Typing**: Type text on your phone keyboard with instant real-time synchronization to active PC text fields.
- **Windows Shortcuts Bar**: Instant 1-tap buttons for `Select All`, `Copy`, `Paste`, `Middle Click`, `Task View`, `Show Desktop`, `Win+D`, `Tab`, and `Esc`.

### 📋 3. Cross-Device Shared Clipboard Sync
- **Instant Bi-Directional Clipboard Sync**: Copy text on your Android phone and paste directly on your PC (`Ctrl + V`), or fetch text from your Windows PC clipboard straight to your phone.

### 📁 4. Remote PC File Manager & Transfer
- **Remote File Browser**: Browse C:\, D:\ drives and folders on your PC in real-time.
- **Directory Breadcrumb History**: Hardware back button and app bar back arrow navigate cleanly up folder levels before returning to the dashboard.
- **Chunked File Transfer**: High-speed chunked upload/download with SHA-256 checksum integrity verification.

### 📊 5. Real-Time System Monitor & Telemetry
- **Hardware Telemetry**: Real-time streaming of Processor (CPU %), Memory (RAM GB usage and total capacity), and Power / Battery % [Charging State].
- **Process Manager**: Real-time view of active Windows applications, window titles, PIDs, and memory footprints.

### ⚡ 6. Power Controls
- **1-Tap Power Commands**: Shutdown, Restart, Sleep, and Lock PC with safety confirmation dialogs.

---

## 🛠️ Architecture & Tech Stack

```
   ┌───────────────────────┐                     ┌───────────────────────────┐
   │  Android Mobile App   │  ◄── WebSocket ──►  │    Windows C# Agent       │
   │  (Flutter & Dart)     │  ◄── Bluetooth ──►  │  (.NET 8 WPF Companion)   │
   └───────────────────────┘                     └───────────────────────────┘
```

- **Android Mobile App (`/lib`)**:
  - **Framework**: Flutter 3.x & Dart
  - **State Management**: Riverpod (`flutter_riverpod`)
  - **Dependencies**: `shared_preferences`, `file_picker`, `crypto`, `sqflite`, `mobile_scanner`, `web_socket_channel`.
- **Windows Companion Agent (`/windows-agent`)**:
  - **Framework**: C# .NET 8 WPF (`net8.0-windows10.0.19041.0`)
  - **WebSocket Server**: `Fleck` (`ws://0.0.0.0:8443`)
  - **Bluetooth RFCOMM**: `32feet.NET` (`InTheHand.Net.Bluetooth`)
  - **Win32 Native Integration**: `mouse_event`, `SetCursorPos`, `VkKeyScan`, `SendInput`, `NAudio` MMDevice API, `GlobalMemoryStatusEx`.

---

## 📂 Project Directory Structure

```
pcmouse/
├── lib/                                    # Android Flutter Application
│   ├── main.dart                           # Application Entry Point & ProviderScope
│   ├── data/
│   │   └── repositories/
│   │       ├── local_network_repository.dart  # WebSocket Client Communication Transport
│   │       ├── bluetooth_repository.dart      # Bluetooth RFCOMM Serial Transport
│   │       └── unified_connection_manager.dart# Connection Failover Switcher
│   └── presentation/
│       ├── dashboard/dashboard_screen.dart # Main Control Dashboard Grid
│       ├── touchpad/touchpad_screen.dart   # Precision Trackpad & Gestures
│       ├── file_manager/file_manager_screen.dart # Remote PC Storage File Manager
│       ├── system_monitor/system_monitor_screen.dart # Hardware Telemetry & Process List
│       └── power_control/power_control_dialog.dart   # Power Control Confirmation Dialogs
├── windows-agent/PcmouseAgent/             # Windows C# Companion Agent
│   ├── Program.cs                          # Agent Entry Point
│   ├── MainWindow.xaml                     # WPF Status Window
│   └── Modules/
│       ├── MouseController.cs              # Win32 Hardware Accelerated Cursor Engine
│       ├── KeyboardController.cs           # Win32 SendInput & VkKeyScan Controller
│       ├── SystemMonitor.cs                # Win32 GlobalMemoryStatusEx & CPU Monitor
│       ├── ClipboardManager.cs             # Windows STA Thread Shared Clipboard
│       ├── WebSocketServer.cs              # Fleck Async WebSocket Listener
│       └── ConnectionManager.cs            # JSON Packet Protocol Router
├── shared-protocol/                        # JSON Protocol Specifications
│   └── packets/protocol_spec.json
└── README.md
```

---

## 🚀 Getting Started

### 1. Prerequisites
- **For Windows Companion Agent**: Windows 10/11 with [.NET 8.0 SDK / Runtime](https://dotnet.microsoft.com/download/dotnet/8.0).
- **For Android Mobile App**: Android Device running Android 7.0+ (API 24+) with Flutter SDK 3.x installed.

### 2. Building & Running Windows Companion Agent
```powershell
# Navigate to Windows Agent directory
cd windows-agent\PcmouseAgent

# Build project
dotnet build --configuration Release

# Run Agent
dotnet run --configuration Release
```
> The Agent will start the WebSocket server listening on `ws://0.0.0.0:8443` and publish its local IP address and QR code for instant phone pairing.

### 3. Running Android App
```bash
# Get Flutter dependencies
flutter pub get

# Connect your Android device via USB / Wireless ADB and run
flutter run -d <your-device-id>
```

---

## 📡 Protocol Specification

Communication packets are exchanged via CamelCase JSON frames:

### Mouse Delta Event
```json
{
  "type": "MOUSE_EVENT",
  "payload": {
    "action": "MOVE",
    "dx": 12,
    "dy": -8
  }
}
```

### Keyboard Event
```json
{
  "type": "KEYBOARD_EVENT",
  "payload": {
    "action": "TEXT",
    "text": "Hello Windows!"
  }
}
```

### Shared Clipboard Sync
```json
{
  "type": "CLIPBOARD_SET",
  "payload": {
    "text": "Copied Text from Mobile Device"
  }
}
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
