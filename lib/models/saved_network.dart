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
