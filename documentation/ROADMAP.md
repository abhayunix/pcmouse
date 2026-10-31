# Remote PC Controller System - Deployment & Build Guide

## Overview
This production-quality Remote PC Controller solution comprises:
1. **Android App**: Developed using Flutter & Dart.
2. **Windows PC Agent**: Developed using C# .NET 8 WPF.

---

## Prerequisites

### Windows PC Agent:
- Windows 10 or Windows 11 Desktop environment.
- .NET 8 Desktop Runtime.
- Bluetooth adapter (for Bluetooth RFCOMM mode).

### Android App:
- Flutter SDK `>=3.2.0`.
- Android 8.0+ (API level 26 or higher).
- Bluetooth, Camera (for QR scan), and Local Storage permissions.

---

## Build & Launch Instructions

### 1. Launching Windows Companion Agent (C# WPF)

Open PowerShell in the project directory:

```powershell
cd windows-agent\PcmouseAgent
dotnet run --configuration Release
```

Or open `windows-agent\PcmouseAgent.sln` in Visual Studio 2022 and press **F5**.

The PC Agent window will launch, display your Local IP, start listening on WebSocket `ws://0.0.0.0:8443` and Bluetooth RFCOMM, and generate a 6-digit pairing PIN with a QR Code.

---

## 2. Launching Android Mobile App (Flutter)

In the root directory:

```bash
flutter pub get
flutter run -d <your-android-device>
```

To build a standalone production APK:

```bash
flutter build apk --release
```

---

## How to Pair & Use

1. Launch **PC Mouse Agent** on your Windows laptop.
2. Open **Remote PC Controller** app on your Android smartphone.
3. Tap the **QR Scanner** icon on the top app bar of the Android app.
4. Point your phone camera at the QR code on the PC Agent screen (or manually enter the IP and 6-digit PIN).
5. Once authorized, tap any remote control module:
   - **Touchpad Mouse**: Slide finger for relative cursor movement, tap to click, long-press for right-click, vertical scroll bar, and left/right button bars.
   - **Remote Keyboard**: Soft keyboard, special keys, function keys `F1-F12`, and quick shortcuts (`Ctrl+C`, `Ctrl+V`, `Alt+Tab`, `Win+D`).
   - **File Manager**: Browse PC directories, pick local files from Android, and upload with progress bar & SHA-256 checksum verification.
   - **System Monitor**: Real-time CPU %, RAM %, Battery % telemetry, and process task manager.
   - **Power Controls**: Confirmation dialogs for Lock Workstation, Sleep, Restart, and Shutdown.
