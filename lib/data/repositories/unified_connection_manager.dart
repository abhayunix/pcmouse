import 'dart:async';
import 'local_network_repository.dart';
import 'bluetooth_repository.dart';

enum TransportType { bluetooth, localNetwork, internet, none }

class UnifiedConnectionState {
  final TransportType activeTransport;
  final bool isConnected;
  final String statusMessage;

  UnifiedConnectionState({
    required this.activeTransport,
    required this.isConnected,
    required this.statusMessage,
  });
}

class UnifiedConnectionManager {
  final LocalNetworkRepository localNetworkRepo;
  final BluetoothRepository bluetoothRepo;

  final StreamController<UnifiedConnectionState> _stateController = StreamController.broadcast();
  Stream<UnifiedConnectionState> get stateStream => _stateController.stream;

  TransportType _currentTransport = TransportType.none;
  TransportType get currentTransport => _currentTransport;

  bool _isConnecting = false;

  UnifiedConnectionManager({
    required this.localNetworkRepo,
    required this.bluetoothRepo,
  });

  /// Automatically select and establish best available connection
  Future<bool> autoConnect({
    required String ip,
    required int port,
    required String pairingCode,
    String? btMacAddress,
  }) async {
    if (_isConnecting) return false;
    _isConnecting = true;

    _emitState(TransportType.none, false, 'Scanning available connection transports...');

    // 1. Try Local Network / Mobile Hotspot WebSocket (Fastest bandwidth)
    _emitState(TransportType.localNetwork, false, 'Attempting Local Network / Hotspot (WSS)...');
    bool lanOk = await localNetworkRepo.connect(ip, port);
    if (lanOk) {
      bool authOk = await localNetworkRepo.sendHandshake(pairingCode);
      if (authOk) {
        _currentTransport = TransportType.localNetwork;
        _isConnecting = false;
        _emitState(TransportType.localNetwork, true, 'Connected via Local Network / Hotspot');
        return true;
      }
    }

    // 2. Try Bluetooth Classic RFCOMM fallback
    if (btMacAddress != null && btMacAddress.isNotEmpty) {
      _emitState(TransportType.bluetooth, false, 'Fallback to Bluetooth Classic (RFCOMM)...');
      bool btOk = await bluetoothRepo.connect(btMacAddress);
      if (btOk) {
        _currentTransport = TransportType.bluetooth;
        _isConnecting = false;
        _emitState(TransportType.bluetooth, true, 'Connected via Bluetooth Classic');
        return true;
      }
    }

    // 3. Connection failed on all candidate transports
    _currentTransport = TransportType.none;
    _isConnecting = false;
    _emitState(TransportType.none, false, 'Failed to connect on any transport.');
    return false;
  }

  void _emitState(TransportType transport, bool isConnected, String message) {
    _stateController.add(
      UnifiedConnectionState(
        activeTransport: transport,
        isConnected: isConnected,
        statusMessage: message,
      ),
    );
  }

  void disconnectAll() {
    localNetworkRepo.disconnect();
    bluetoothRepo.disconnect();
    _currentTransport = TransportType.none;
    _emitState(TransportType.none, false, 'Disconnected');
  }
}
