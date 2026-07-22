import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/automation_model.dart';
import 'bluetooth_service.dart';

/// Local notifications (§8.6 step 1 + §8.9 item 5): pre-session dock
/// reminders (~5 min before a phoneAway window), window-start notices for
/// other commitments, and pending-change promotion notices.
///
/// Everything is OS-scheduled and local-only — consistent with the
/// no-midnight-push decision (§7.3): the phone never needs to be running at a
/// particular moment; the OS delivers what was scheduled while the app was
/// last open, and we reschedule the coming 48 h on every schedule change and
/// app foreground.
class NotificationService {
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'impulse_commitments',
    'Commitments',
    channelDescription:
        'Dock reminders and commitment updates from your own schedule',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      );
      _ready = (await _plugin.initialize(settings: settings)) ?? false;
    } catch (_) {
      // Platform without the plugin (tests/desktop variants): stay silent.
      _ready = false;
    }
  }

  /// A TZDateTime for the same absolute instant as [dt]. `tz.local` may not
  /// be configured, so express the instant in UTC — the moment is identical.
  tz.TZDateTime _instant(DateTime dt) => tz.TZDateTime.from(dt.toUtc(), tz.UTC);

  /// Deterministic 31-bit id per (event, day, kind) so rescheduling replaces
  /// rather than duplicates.
  int _id(String eventId, DateTime day, int kind) =>
      (Object.hash(eventId, day.year * 10000 + day.month * 100 + day.day,
          kind)) &
      0x7FFFFFFF;

  /// Reschedule the coming 48 h of window notices from the authored schedule:
  /// phoneAway → "time to dock" ~5 min before the window; everything else →
  /// a calm start notice. Cancels previous schedules first.
  Future<void> rescheduleWindowNotices(List<Automation> schedule) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();
      final anchors = BluetoothService().anchors;

      for (int dayOffset = 0; dayOffset < 2; dayOffset++) {
        final day = DateTime(now.year, now.month, now.day)
            .add(Duration(days: dayOffset));
        for (final a in schedule) {
          if (a.negate || !a.appearsOnDate(day)) continue;
          final start = day.add(Duration(minutes: a.startMinutes));

          if (a.criteria == Criteria.phoneAway) {
            final remindAt = start.subtract(const Duration(minutes: 5));
            if (remindAt.isAfter(now)) {
              final anchorName = anchors
                      .where((x) => x.id == a.anchorId)
                      .firstOrNull
                      ?.name ??
                  'its dock';
              await _plugin.zonedSchedule(
                id: _id(a.id, day, 1),
                title: 'Time to dock your phone',
                body:
                    'Your phone-free block starts in 5 minutes — set the '
                    'phone at $anchorName and open the app.',
                scheduledDate: _instant(remindAt),
                notificationDetails: _details,
                androidScheduleMode:
                    AndroidScheduleMode.inexactAllowWhileIdle,
              );
            }
          } else if (start.isAfter(now)) {
            await _plugin.zonedSchedule(
              id: _id(a.id, day, 2),
              title: 'A commitment just started',
              body: '${a.criteria.label} until ${_fmtMinutes(a.endMinutes)} '
                  '— past-you set this up.',
              scheduledDate: _instant(start),
              notificationDetails: _details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          }
        }
      }
    } catch (_) {
      // Scheduling is best-effort; the in-app surfaces remain the truth.
    }
  }

  /// Immediate notice that a queued easing has taken effect (§8.9 item 5).
  Future<void> notifyPromotion(String description) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
        title: 'A change you queued is now live',
        body: description.isEmpty
            ? 'An easing you asked for has taken effect.'
            : description,
        notificationDetails: _details,
      );
    } catch (_) {}
  }

  /// Anchor distress notice (§8.14): an anchor can't get on its network and we
  /// can't fix it from saved credentials. State the consequence, stay calm
  /// (impulse_overview voice). Tapping is handled by the app's Devices surface.
  Future<void> notifyAnchorDistress(String anchorName, String ssid) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: ('distress:$anchorName').hashCode & 0x7FFFFFFF,
        title: '$anchorName can’t get online',
        body: ssid.isEmpty
            ? '$anchorName isn’t connected to WiFi. Until it’s back online it '
                'won’t sound.'
            : '$anchorName can’t get on "$ssid". Until it’s back online it '
                'won’t sound. Tap to add the password.',
        notificationDetails: _details,
      );
    } catch (_) {}
  }

  String _fmtMinutes(int minutes) {
    final h24 = minutes ~/ 60;
    final m = (minutes % 60).toString().padLeft(2, '0');
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h:$m ${h24 < 12 ? 'AM' : 'PM'}';
  }
}
