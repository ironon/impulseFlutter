import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../services/watch_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/policy_verdict.dart';

/// The pending-changes view (§8.9 item 5): every queued loosening with its
/// "takes effect no earlier than" time. Prefers the watch's authoritative
/// …001A queue when the characteristic exists; otherwise the interim app queue.
class PendingChangesScreen extends StatelessWidget {
  const PendingChangesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final watchEntries = app.watchPendingEntries;
    final appRows = app.pendingRows;

    return Scaffold(
      appBar: AppBar(title: const Text('Pending changes')),
      body: RefreshIndicator(
        color: AppTheme.lightOrange,
        onRefresh: () async {
          await app.promoteDuePending();
          await app.refreshWatchPending();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _sourceBanner(watchEntries != null),
            const SizedBox(height: 12),
            if (watchEntries != null)
              ...(watchEntries.isEmpty
                  ? [_emptyState()]
                  : watchEntries.map((e) => _watchEntryTile(app, e)))
            else
              ...(appRows.isEmpty
                  ? [_emptyState()]
                  : appRows.map(_appRowTile)),
          ],
        ),
      ),
    );
  }

  Widget _sourceBanner(bool fromWatch) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.cardGrey,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(fromWatch ? Icons.watch : Icons.phone_iphone,
                color: AppTheme.textGrey, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fromWatch
                    ? 'Showing the watch\'s own queue — it holds the line even '
                        'if the app is reinstalled.'
                    : 'Showing this phone\'s queue. Connect the watch to see '
                        'its own record.',
                style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
              ),
            ),
          ],
        ),
      );

  Widget _emptyState() => const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.textGrey, size: 40),
            SizedBox(height: 12),
            Text('Nothing waiting',
                style: TextStyle(color: AppTheme.textWhite, fontSize: 16)),
            SizedBox(height: 6),
            Text(
              'Changes that ease a settled commitment wait here for a day '
              'before they take effect.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
            ),
          ],
        ),
      );

  Widget _appRowTile(PendingChangeRow row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.hourglass_top, color: Colors.amber),
        title: Text(
          row.description.isEmpty ? 'Eased commitment' : row.description,
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 14),
        ),
        subtitle: Text(
          'Takes effect no earlier than ${formatWhen(row.applyAfter)}',
          style: const TextStyle(color: Colors.amber, fontSize: 12),
        ),
      ),
    );
  }

  Widget _watchEntryTile(AppState app, PendingChangeEntry e) {
    final eta = DateTime.now().add(Duration(seconds: e.secondsUntilApply));
    final target =
        app.schedule.where((a) => a.id == e.eventUuid).firstOrNull;
    // Wire mapping (firmware §9.5): 0=delete, 1=loosen-modify,
    // 2=negate-day, 3=setting change.
    final what = switch (e.changeType) {
      0 => 'Remove commitment',
      1 => 'Eased commitment',
      2 => 'Skip one day',
      3 => 'Setting change',
      _ => 'Pending change',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.hourglass_top, color: Colors.amber),
        title: Text(
          target != null ? '$what — ${_timeRange(target)}' : what,
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 14),
        ),
        subtitle: Text(
          'Takes effect no earlier than ${formatWhen(eta)}',
          style: const TextStyle(color: Colors.amber, fontSize: 12),
        ),
      ),
    );
  }

  String _timeRange(dynamic a) {
    String f(TimeOfDay t) {
      final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
    }

    return '${f(a.startTime)}–${f(a.endTime)}';
  }
}
