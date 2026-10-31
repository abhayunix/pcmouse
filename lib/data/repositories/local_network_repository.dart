import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsConnectionState { disconnected, connecting, connected, error }

class LocalNetworkRepository {
  WebSocketChannel? _channel;
  final StreamController<WsConnectionState> _stateController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get state => _state;

  Stream<WsConnectionState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  String? _sessionToken;

  /// Connect to Windows Agent WebSocket Server
  Future<bool> connect(String ip, int port) async {
    try {
      _updateState(WsConnectionState.connecting);
      final uri = Uri.parse('ws://$ip:$port');

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _updateState(WsConnectionState.connected);

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString()) as Map<String, dynamic>;
            _messageController.add(data);
          } catch (e) {
            debugPrint('Error parsing incoming WS frame: $e');
          }
        },
        onError: (error) {
          debugPrint('WS error: $error');
          _updateState(WsConnectionState.error);
        },
        onDone: () {
          debugPrint('WS connection closed');
          _updateState(WsConnectionState.disconnected);
        },
      );

      return true;
    } catch (e) {
      debugPrint('WS connect error: $e');
      _updateState(WsConnectionState.error);
      return false;
    }
  }

  /// Perform initial Handshake & Pairing PIN validation
  Future<bool> sendHandshake(String pairingCode) async {
    if (_state != WsConnectionState.connected) return false;

    final completer = Completer<bool>();

    late StreamSubscription sub;
    sub = messageStream.listen((msg) {
      if (msg['type'] == 'HANDSHAKE_RESP') {
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null && payload['success'] == true) {
          _sessionToken = payload['token'] as String?;
          completer.complete(true);
        } else {
          completer.complete(false);
        }
        sub.cancel();
      }
    });

    sendFrame(
      type: 'HANDSHAKE_REQ',
      payload: {'code': pairingCode},
    );

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub.cancel();
        return false;
      },
    );
  }

  /// Send relative or absolute mouse event
  void sendMouseEvent({
    required String action,
    int dx = 0,
    int dy = 0,
    double absoluteX = -1.0,
    double absoluteY = -1.0,
    String button = 'NONE',
    bool isDown = false,
    int scrollDeltaY = 0,
    int scrollDeltaX = 0,
  }) {
    sendFrame(
      type: 'MOUSE_EVENT',
      payload: {
        'action': action,
        'dx': dx,
        'dy': dy,
        'absoluteX': absoluteX,
        'absoluteY': absoluteY,
        'button': button,
        'isDown': isDown,
        'scrollDeltaY': scrollDeltaY,
        'scrollDeltaX': scrollDeltaX,
      },
    );
  }

  /// Send keyboard input or shortcut
  void sendKeyboardEvent({
    required String action,
    int keyCode = 0,
    String text = '',
  }) {
    sendFrame(
      type: 'KEYBOARD_EVENT',
      payload: {
        'action': action,
        'keyCode': keyCode,
        'text': text,
      },
    );
  }

  /// Sync phone text directly into Windows PC Clipboard
  void sendClipboardText(String text) {
    sendFrame(
      type: 'CLIPBOARD_SET_REQ',
      payload: {'text': text},
    );
  }

  /// Fetch text from Windows PC Clipboard
  void requestClipboardText() {
    sendFrame(
      type: 'CLIPBOARD_GET_REQ',
      payload: {},
    );
  }

  /// Send system volume control command
  void sendVolumeCommand(String action, {double level = 0.5}) {
    sendFrame(
      type: 'VOLUME_COMMAND',
      payload: {
        'action': action,
        'level': level,
      },
    );
  }

  /// Send power state command (Shutdown, Restart, Lock, Sleep)
  void sendSystemCommand(String action, {bool force = false}) {
    sendFrame(
      type: 'SYSTEM_COMMAND',
      payload: {
        'action': action,
        'force': force,
      },
    );
  }

  /// Raw packet envelope dispatch
  void sendFrame({required String type, required Map<String, dynamic> payload}) {
    if (_state != WsConnectionState.connected || _channel == null) return;

    final frame = {
      'version': 1,
      'msgId': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'token': _sessionToken ?? '',
      'payload': payload,
    };

    _channel!.sink.add(jsonEncode(frame));
  }

  void _updateState(WsConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _updateState(WsConnectionState.disconnected);
  }
}
