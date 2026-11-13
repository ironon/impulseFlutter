// One saved WiFi network (spec v2 §4.4 / §8.15).
//
// Immutable value type only — persistence and the 4-network cap live in
// SavedNetworksStore, and passwords are kept in flutter_secure_storage rather
// than alongside the SSID list.
//
// This is the ONLY credential source an offer (…0003) or a watch push (…0011)
// can draw from: neither iOS nor Android hands an app the password of the
// network the phone is on (§8.14 platform constraint).

/// A WiFi network the user typed into the app (§8.15 / §4.4). This is the only
/// source of credentials an anchor offer or a watch push can draw from — the OS
/// never hands the app the password of the network the phone is on (§8.14
/// platform constraint), so nothing here is auto-populated.
class SavedNetwork {
  final String ssid;
  final String password;

  const SavedNetwork({required this.ssid, required this.password});

  SavedNetwork copyWith({String? ssid, String? password}) => SavedNetwork(
        ssid: ssid ?? this.ssid,
        password: password ?? this.password,
      );
}
