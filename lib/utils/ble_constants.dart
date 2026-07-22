/// BLE UUID constants — must match firmware exactly.
class BleConstants {
  /// Max saved WiFi networks the app keeps (§8.15). **Must equal the firmware
  /// `ANCHOR_WIFI_MAX_CRED_SLOTS`** (§4.4) — a longer app list than the anchor's
  /// slot table makes offers silently evict each other. Reference this constant;
  /// never hardcode a second literal (§0.3 cross-cutting note).
  static const int anchorWifiMaxCredSlots = 4;

  // ── Anchor ────────────────────────────────────────────────────────────────
  static const String anchorServiceUuid        = '4a0f0001-f8ce-11ee-8001-020304050607';
  static const String anchorIdentifyCharUuid   = '4a0f0002-f8ce-11ee-8001-020304050607';
  static const String anchorWifiCredCharUuid   = '4a0f0003-f8ce-11ee-8001-020304050607';
  static const String anchorSettingsCharUuid   = '4a0f0004-f8ce-11ee-8001-020304050607';
  static const String anchorWifiStatusCharUuid = '4a0f000e-f8ce-11ee-8001-020304050607'; // §6.2 …000E (v0.8)
  static const String anchorSchedCtrlCharUuid  = '4a0f0005-f8ce-11ee-8001-020304050607';
  static const String anchorSchedDataCharUuid  = '4a0f0006-f8ce-11ee-8001-020304050607';
  static const String anchorToggleCharUuid     = '4a0f0007-f8ce-11ee-8001-020304050607';
  static const String anchorProxVectorCharUuid = '4a0f0008-f8ce-11ee-8001-020304050607'; // watch-only write
  static const String anchorProxScoreCharUuid  = '4a0f0009-f8ce-11ee-8001-020304050607'; // read + notify
  static const String anchorFpCtrlCharUuid     = '4a0f000a-f8ce-11ee-8001-020304050607'; // fingerprint ctrl
  static const String anchorFpDataCharUuid     = '4a0f000b-f8ce-11ee-8001-020304050607'; // fingerprint data
  static const String anchorDockRegisterCharUuid = '4a0f000c-f8ce-11ee-8001-020304050607'; // dock register
  static const String anchorDockStatusCharUuid   = '4a0f000d-f8ce-11ee-8001-020304050607'; // dock status

  // ── Watch ─────────────────────────────────────────────────────────────────
  static const String watchServiceUuid         = '4a0f0010-f8ce-11ee-8001-020304050607';
  static const String watchWifiCredCharUuid    = '4a0f0011-f8ce-11ee-8001-020304050607';
  static const String watchSchedCtrlCharUuid   = '4a0f0012-f8ce-11ee-8001-020304050607';
  static const String watchSchedDataCharUuid   = '4a0f0013-f8ce-11ee-8001-020304050607';
  static const String watchSettingsCharUuid    = '4a0f0014-f8ce-11ee-8001-020304050607';
  static const String watchSeenAnchorsCharUuid = '4a0f0015-f8ce-11ee-8001-020304050607';
  static const String watchStatusCharUuid      = '4a0f0016-f8ce-11ee-8001-020304050607';
  static const String watchAnchorIpCharUuid    = '4a0f0017-f8ce-11ee-8001-020304050607';
  static const String watchLedConfigCharUuid   = '4a0f0018-f8ce-11ee-8001-020304050607'; // format TBD
  static const String watchTimeCharUuid        = '4a0f0019-f8ce-11ee-8001-020304050607'; // §8.11 (probe)
  static const String watchPendingCharUuid     = '4a0f001a-f8ce-11ee-8001-020304050607'; // §9.5 (probe)
  static const String watchEmergencyPassCharUuid = '4a0f001b-f8ce-11ee-8001-020304050607'; // §9.6 (probe)

  // ── Manufacturer data ─────────────────────────────────────────────────────
  // Custom company ID (0xFFFF) used in place of Apple's 0x004C so that iOS
  // passes the manufacturer data through to third-party apps.
  static const int impulseCompanyId = 0xFFFF;
  static const int iBeaconType      = 0x02;
  static const int iBeaconLength    = 0x15;
}
