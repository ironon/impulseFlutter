// Impulse app — the GATT contract.
//
// Every UUID and advertising constant this app speaks lives here, and must stay
// byte-identical with the firmware. The contract has four declarations that must
// move together (see "add a new characteristic" in CODEMAP.md):
//   1. firmware_spec_v3_nrf.md §4 — the contract of record.
//   2. nrf_firmware/src/ble/ble_uuids.h — the IMPULSE_UUID_* #defines.
//   3. this file.
//   4. phone_sim/impulse_phone/constants.py.
//
// Several values below are ESP32-era and now dead on the nRF build: v3 §4.8
// deleted the anchor's proximity/fingerprint/calibration block and the watch's
// calibration control. The constants stay declared so the app degrades by
// probe (a characteristic that is absent simply never binds), but do not
// assume the device serves them.
//
// There is no runtime negotiation of payload layouts: a parser that disagrees
// with the firmware silently mis-decodes. Characteristics are bound by UUID at
// connect time (WatchService._bindCharacteristics for the watch;
// AnchorService / AnchorTelemetrySession / DockSessionService for anchors), so
// adding one needs a constant here, a bind there, and a decoder beside it.

/// BLE UUID constants — must match firmware exactly.
class BleConstants {
  /// Max saved WiFi networks the app keeps (§8.15). **Must equal the firmware
  /// `ANCHOR_WIFI_MAX_CRED_SLOTS`** (§4.4) — a longer app list than the anchor's
  /// slot table makes offers silently evict each other. Reference this constant;
  /// never hardcode a second literal (§0.3 cross-cutting note).
  static const int anchorWifiMaxCredSlots = 4;

  // ── Anchor ────────────────────────────────────────────────────────────────
  // The anchor service is scanned for (advertising service UUID), and its
  // characteristics are discovered per-connection. The app only ever WRITES the
  // Identify / WiFi Credentials / Toggle / Dock Register characteristics and
  // READS+subscribes WiFi Status, Prox Score and Dock Status; the schedule and
  // fingerprint Ctrl/Data pairs are declared for completeness but unused by
  // this app (schedules reach anchors over HTTP, §7.3).
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
  static const String anchorCalibModeCharUuid    = '4a0f000f-f8ce-11ee-8001-020304050607'; // calibration-v2 phase (…000F)
  /// Debug Telemetry **v2** (contract §4.3/§4.4): read + notify, where notify
  /// is the 8-byte §4.5 change hint only. Appended last in the anchor service
  /// by R6 so no existing attribute handle moves.
  static const String anchorDebugTelemetryV2CharUuid =
      '4a0f0020-f8ce-11ee-8001-020304050607';

  // ── Watch ─────────────────────────────────────────────────────────────────
  // The watch is the root of trust: it owns the schedule and the clock. This app
  // writes credentials/settings/schedule/time/IP table and reads status, seen
  // anchors, pending changes, emergency-pass ledger and calibration progress.
  // The last five (…0019, …001A, …001B, …001C, …001D) are runtime-probed — see
  // WatchService.hasTimeCharacteristic and friends — so a firmware build without
  // them degrades instead of throwing.
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
  static const String watchCalibCtrlCharUuid   = '4a0f001c-f8ce-11ee-8001-020304050607'; // §4.10.7 calibration burst (probe)
  /// Debug Telemetry **v2** (contract §4.1/§4.2): read + notify, where notify
  /// is the 8-byte §4.5 change hint only. Appended last in the watch service by
  /// R6 so no existing attribute handle moves.
  static const String watchDebugTelemetryV2CharUuid =
      '4a0f001d-f8ce-11ee-8001-020304050607';

  // ── Manufacturer data ─────────────────────────────────────────────────────
  // Custom company ID (0xFFFF) used in place of Apple's 0x004C so that iOS
  // passes the manufacturer data through to third-party apps.
  static const int impulseCompanyId = 0xFFFF;
  static const int iBeaconType      = 0x02;
  static const int iBeaconLength    = 0x15;
}
