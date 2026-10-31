class PairedPcModel {
  final String id;
  final String pcName;
  final String ipAddress;
  final int port;
  final String sessionToken;
  final bool isLastConnected;
  final DateTime lastSeen;

  PairedPcModel({
    required this.id,
    required this.pcName,
    required this.ipAddress,
    required this.port,
    required this.sessionToken,
    this.isLastConnected = false,
    required this.lastSeen,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pcName': pcName,
      'ipAddress': ipAddress,
      'port': port,
      'sessionToken': sessionToken,
      'isLastConnected': isLastConnected ? 1 : 0,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
    };
  }

  factory PairedPcModel.fromMap(Map<String, dynamic> map) {
    return PairedPcModel(
      id: map['id'] ?? '',
      pcName: map['pcName'] ?? 'Unknown PC',
      ipAddress: map['ipAddress'] ?? '127.0.0.1',
      port: map['port'] ?? 8443,
      sessionToken: map['sessionToken'] ?? '',
      isLastConnected: (map['isLastConnected'] ?? 0) == 1,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['lastSeen'] ?? 0),
    );
  }
}
