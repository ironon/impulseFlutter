import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_network.dart';
import '../utils/ble_constants.dart';

/// Persistent store for the app's saved WiFi networks (§8.15).
///
/// This is **infrastructure, not a form**: the single credential source for the
/// watch push (`…0011`), anchor (re-)provisioning (`…0003`, §8.14), and the
/// watch's autonomous repair (firmware §5.5.3 — it can only offer what it holds).
///
/// SSIDs + ordering live in `shared_preferences`; passwords live in
/// `flutter_secure_storage` (Keychain / Keystore) — real credentials must not
/// sit in a plaintext prefs backup. Capped at [maxNetworks], which mirrors the
/// firmware credential-slot count so app and anchor never disagree.
class SavedNetworksStore {
  SavedNetworksStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  static final SavedNetworksStore _instance = SavedNetworksStore();
  factory SavedNetworksStore.instance() => _instance;

  final FlutterSecureStorage _secure;

  static const String _ssidsKey = 'saved_network_ssids';
  static const String _pwKeyPrefix = 'wifi_pw_';

  /// == firmware `ANCHOR_WIFI_MAX_CRED_SLOTS`. Referenced, never re-literalled.
  static int get maxNetworks => BleConstants.anchorWifiMaxCredSlots;

  List<SavedNetwork> _networks = [];
  bool _loaded = false;

  List<SavedNetwork> get networks => List.unmodifiable(_networks);
  bool get isEmpty => _networks.isEmpty;
  bool get isFull => _networks.length >= maxNetworks;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final ssids = prefs.getStringList(_ssidsKey) ?? const [];
    final out = <SavedNetwork>[];
    for (final ssid in ssids) {
      final pw = await _secure.read(key: _pwKeyPrefix + ssid) ?? '';
      out.add(SavedNetwork(ssid: ssid, password: pw));
    }
    _networks = out;
    _loaded = true;
  }

  Future<void> _persistOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ssidsKey, _networks.map((n) => n.ssid).toList());
  }

  SavedNetwork? bySsid(String ssid) {
    for (final n in _networks) {
      if (n.ssid == ssid) return n;
    }
    return null;
  }

  /// Adds a new network, or updates the password if the SSID already exists.
  /// Presented in the order added (§8.15 — no user reordering; the anchor's own
  /// slot ordering decides what it actually uses). Returns false when the list
  /// is full and this is a genuinely new SSID.
  Future<bool> addOrUpdate(String ssid, String password) async {
    ssid = ssid.trim();
    if (ssid.isEmpty) return false;
    final idx = _networks.indexWhere((n) => n.ssid == ssid);
    if (idx >= 0) {
      _networks[idx] = SavedNetwork(ssid: ssid, password: password);
    } else {
      if (isFull) return false;
      _networks.add(SavedNetwork(ssid: ssid, password: password));
    }
    await _secure.write(key: _pwKeyPrefix + ssid, value: password);
    await _persistOrder();
    return true;
  }

  /// Renames an existing network's SSID (used by the edit sheet when the SSID
  /// field is changed). Preserves list position.
  Future<bool> rename(String oldSsid, String newSsid, String password) async {
    newSsid = newSsid.trim();
    if (newSsid.isEmpty) return false;
    final idx = _networks.indexWhere((n) => n.ssid == oldSsid);
    if (idx < 0) return addOrUpdate(newSsid, password);
    // Reject a collision with a different existing entry.
    final clash = _networks.indexWhere((n) => n.ssid == newSsid);
    if (clash >= 0 && clash != idx) return false;
    _networks[idx] = SavedNetwork(ssid: newSsid, password: password);
    if (newSsid != oldSsid) {
      await _secure.delete(key: _pwKeyPrefix + oldSsid);
    }
    await _secure.write(key: _pwKeyPrefix + newSsid, value: password);
    await _persistOrder();
    return true;
  }

  /// "Stop using this network" (§8.15). Honest wording: this cannot retract
  /// credentials a device already stored — it only stops the app/watch offering
  /// it going forward.
  Future<void> remove(String ssid) async {
    _networks.removeWhere((n) => n.ssid == ssid);
    await _secure.delete(key: _pwKeyPrefix + ssid);
    await _persistOrder();
  }
}
