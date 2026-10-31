import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

enum BtConnectionState { disconnected, connecting, connected, error }

class BluetoothRepository {
  BluetoothConnection? _connection;
  final StreamController<BtConnectionState> _stateController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();

  BtConnectionState _state = BtConnectionState.disconnected;
  BtConnectionState get state => _state;

  Stream<BtConnectionState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// Get list of paired / bonded Bluetooth devices on Android
  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      debugPrint('getPairedDevices error: $e');
      return [];
    }
  }

  /// Connect to Windows PC Bluetooth RFCOMM socket
  Future<bool> connect(String address) async {
    try {
      _updateState(BtConnectionState.connecting);

      _connection = await BluetoothConnection.toAddress(address);
      _updateState(BtConnectionState.connected);

      _connection!.input?.listen((Uint8List data) {
        try {
          String raw = utf8.decode(data);
          for (var line in raw.split('\n')) {
            if (line.trim().isNotEmpty) {
              final parsed = jsonDecode(line.trim()) as Map<String, dynamic>;
              _messageController.add(parsed);
            }
          }
        } catch (e) {
          debugPrint('Error parsing BT input stream: $e');
        }
      }, onDone: () {
        _updateState(BtConnectionState.disconnected);
      }, onError: (err) {
        debugPrint('BT stream error: $err');
        _updateState(BtConnectionState.error);
      });

      return true;
    } catch (e) {
      debugPrint('Bluetooth connect error: $e');
      _updateState(BtConnectionState.error);
      return false;
    }
  }

  /// Send JSON packet envelope over Bluetooth RFCOMM stream
  void sendFrame({required String type, required Map<String, dynamic> payload}) {
    if (_state != BtConnectionState.connected || _connection == null) return;

    final frame = {
      'version': 1,
      'msgId': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    };

    String raw = '${jsonEncode(frame)}\n';
    _connection!.output.add(Uint8List.fromList(utf8.encode(raw)));
  }

  void _updateState(BtConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void disconnect() {
    _connection?.finish();
    _connection = null;
    _updateState(BtConnectionState.disconnected);
  }
}
