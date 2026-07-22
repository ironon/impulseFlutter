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

  /// User-assigned role tag for anchors (§4.4): e.g. "bedroom", "nightstand",
  /// "desk", "phone dock". Null when unassigned.
  final String? role;

  // ── Anchor WiFi provisioning state (§4.4 / §8.14) ──
  /// The `…000E` `state` byte from the last WiFi Status read (0..4), or null if
  /// never read. WiFi state comes from the anchor, not from inference (§8.2).
  final int? lastWifiState;

  /// The SSID the anchor was on / last attempted, from the last `…000E` read.
  final String? lastWifiSsid;

  /// When we last read `…000E` for this anchor.
  final DateTime? lastWifiCheckAt;

  /// `slots_used` from the last read (Advanced-mode display only).
  final int? slotsUsed;

  /// SSIDs this app has already offered to this anchor — prevents re-offering
  /// the same (failing) credentials on every sweep (§4.4). Cleared for an SSID
  /// when the user edits that saved network's password (§8.15 rotated-password
  /// fix path).
  final List<String> offeredSsids;

  /// The distress `state` we last notified the user about, so we notify once
  /// per distress episode and reset when the state changes (§8.14). Null = not
  /// currently notified.
  final int? distressNotifiedState;

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
    this.role,
    this.lastWifiState,
    this.lastWifiSsid,
    this.lastWifiCheckAt,
    this.slotsUsed,
    this.offeredSsids = const [],
    this.distressNotifiedState,
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
        'role': role,
        'lastWifiState': lastWifiState,
        'lastWifiSsid': lastWifiSsid,
        'lastWifiCheckAt': lastWifiCheckAt?.toIso8601String(),
        'slotsUsed': slotsUsed,
        'offeredSsids': offeredSsids,
        'distressNotifiedState': distressNotifiedState,
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
      role: json['role'] as String?,
      lastWifiState: json['lastWifiState'] as int?,
      lastWifiSsid: json['lastWifiSsid'] as String?,
      lastWifiCheckAt: json['lastWifiCheckAt'] == null
          ? null
          : DateTime.parse(json['lastWifiCheckAt'] as String),
      slotsUsed: json['slotsUsed'] as int?,
      offeredSsids:
          (json['offeredSsids'] as List<dynamic>?)?.cast<String>() ?? const [],
      distressNotifiedState: json['distressNotifiedState'] as int?,
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
    String? role,
    int? lastWifiState,
    String? lastWifiSsid,
    DateTime? lastWifiCheckAt,
    int? slotsUsed,
    List<String>? offeredSsids,
    int? distressNotifiedState,
    /// Set true to explicitly clear [distressNotifiedState] back to null (the
    /// `??` pattern otherwise can't unset it — used when a distress episode ends).
    bool clearDistressNotified = false,
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
      role: role ?? this.role,
      lastWifiState: lastWifiState ?? this.lastWifiState,
      lastWifiSsid: lastWifiSsid ?? this.lastWifiSsid,
      lastWifiCheckAt: lastWifiCheckAt ?? this.lastWifiCheckAt,
      slotsUsed: slotsUsed ?? this.slotsUsed,
      offeredSsids: offeredSsids ?? this.offeredSsids,
      distressNotifiedState: clearDistressNotified
          ? null
          : (distressNotifiedState ?? this.distressNotifiedState),
    );
  }
}
