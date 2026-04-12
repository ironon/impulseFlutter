/// BLE UUID constants — must match firmware exactly.
class BleConstants {
  // ── Anchor ────────────────────────────────────────────────────────────────
  static const String anchorServiceUuid        = '4a0f0001-f8ce-11ee-8001-020304050607';
  static const String anchorIdentifyCharUuid   = '4a0f0002-f8ce-11ee-8001-020304050607';
  static const String anchorWifiCredCharUuid   = '4a0f0003-f8ce-11ee-8001-020304050607';
  static const String anchorSettingsCharUuid   = '4a0f0004-f8ce-11ee-8001-020304050607';
  static const String anchorSchedCtrlCharUuid  = '4a0f0005-f8ce-11ee-8001-020304050607';
  static const String anchorSchedDataCharUuid  = '4a0f0006-f8ce-11ee-8001-020304050607';
  static const String anchorToggleCharUuid     = '4a0f0007-f8ce-11ee-8001-020304050607';

  // ── Watch ─────────────────────────────────────────────────────────────────
  static const String watchServiceUuid         = '4a0f0010-f8ce-11ee-8001-020304050607';
  static const String watchWifiCredCharUuid    = '4a0f0011-f8ce-11ee-8001-020304050607';
  static const String watchSchedCtrlCharUuid   = '4a0f0012-f8ce-11ee-8001-020304050607';
  static const String watchSchedDataCharUuid   = '4a0f0013-f8ce-11ee-8001-020304050607';
  static const String watchSettingsCharUuid    = '4a0f0014-f8ce-11ee-8001-020304050607';
  static const String watchSeenAnchorsCharUuid = '4a0f0015-f8ce-11ee-8001-020304050607';
  static const String watchStatusCharUuid      = '4a0f0016-f8ce-11ee-8001-020304050607';
  static const String watchAnchorIpCharUuid    = '4a0f0017-f8ce-11ee-8001-020304050607';

  // ── Manufacturer data ─────────────────────────────────────────────────────
  // Custom company ID (0xFFFF) used in place of Apple's 0x004C so that iOS
  // passes the manufacturer data through to third-party apps.
  static const int impulseCompanyId = 0xFFFF;
  static const int iBeaconType      = 0x02;
  static const int iBeaconLength    = 0x15;
}
