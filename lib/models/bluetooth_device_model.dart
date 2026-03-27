enum DeviceType { watch, anchor, unknown }

class BluetoothDeviceModel {
  final String id;
  final String name;
  final bool isConnected;
  final int rssi;
  final DateTime lastSeen;
  final DeviceType deviceType;

  /// IPv4 address string (e.g. "192.168.1.42"). Null until app resolves it.
  final String? ipAddress;
  final DateTime? ipLastUpdated;

  /// BLE remote ID (MAC on Android, CoreBluetooth UUID on iOS).
  /// Set when the phone directly scanned the device. Null if discovered
  /// only via the watch's SeenAnchors characteristic.
  final String? bleRemoteId;

  const BluetoothDeviceModel({
    required this.id,
    required this.name,
    required this.isConnected,
    required this.rssi,
    required this.lastSeen,
    this.deviceType = DeviceType.unknown,
    this.ipAddress,
    this.ipLastUpdated,
    this.bleRemoteId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isConnected': isConnected,
        'rssi': rssi,
        'lastSeen': lastSeen.toIso8601String(),
        'deviceType': deviceType.name,
        'ipAddress': ipAddress,
        'ipLastUpdated': ipLastUpdated?.toIso8601String(),
        'bleRemoteId': bleRemoteId,
      };

  factory BluetoothDeviceModel.fromJson(Map<String, dynamic> json) {
    return BluetoothDeviceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isConnected: json['isConnected'] as bool,
      rssi: json['rssi'] as int,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == (json['deviceType'] ?? 'unknown'),
        orElse: () => DeviceType.unknown,
      ),
      ipAddress: json['ipAddress'] as String?,
      ipLastUpdated: json['ipLastUpdated'] == null
          ? null
          : DateTime.parse(json['ipLastUpdated'] as String),
      bleRemoteId: json['bleRemoteId'] as String?,
    );
  }

  BluetoothDeviceModel copyWith({
    String? id,
    String? name,
    bool? isConnected,
    int? rssi,
    DateTime? lastSeen,
    DeviceType? deviceType,
    String? ipAddress,
    DateTime? ipLastUpdated,
    String? bleRemoteId,
  }) {
    return BluetoothDeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isConnected: isConnected ?? this.isConnected,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      deviceType: deviceType ?? this.deviceType,
      ipAddress: ipAddress ?? this.ipAddress,
      ipLastUpdated: ipLastUpdated ?? this.ipLastUpdated,
      bleRemoteId: bleRemoteId ?? this.bleRemoteId,
    );
  }
}
