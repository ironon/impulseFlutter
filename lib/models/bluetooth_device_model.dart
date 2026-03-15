class BluetoothDeviceModel {
  final String id;
  final String name;
  final bool isConnected;
  final int rssi;
  final DateTime lastSeen;

  BluetoothDeviceModel({
    required this.id,
    required this.name,
    required this.isConnected,
    required this.rssi,
    required this.lastSeen,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isConnected': isConnected,
      'rssi': rssi,
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  // Create from JSON
  factory BluetoothDeviceModel.fromJson(Map<String, dynamic> json) {
    return BluetoothDeviceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isConnected: json['isConnected'] as bool,
      rssi: json['rssi'] as int,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
    );
  }

  // Create a copy with updated values
  BluetoothDeviceModel copyWith({
    String? id,
    String? name,
    bool? isConnected,
    int? rssi,
    DateTime? lastSeen,
  }) {
    return BluetoothDeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isConnected: isConnected ?? this.isConnected,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
