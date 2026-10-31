class AppConstants {
  static const String appName = 'Remote PC Controller';
  static const String appVersion = '1.0.0';
  static const int defaultPort = 8443;

  // Protocol Types
  static const String typeHandshakeReq = 'HANDSHAKE_REQ';
  static const String typeHandshakeResp = 'HANDSHAKE_RESP';
  static const String typeMouseEvent = 'MOUSE_EVENT';
  static const String typeKeyboardEvent = 'KEYBOARD_EVENT';
  static const String typeSystemCommand = 'SYSTEM_COMMAND';
  static const String typeVolumeCommand = 'VOLUME_COMMAND';
  static const String typeFileTransferStart = 'FILE_TRANSFER_START';
  static const String typeSystemMetricsResp = 'SYSTEM_METRICS_RESP';
}
