import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/automation_model.dart';
import '../services/bluetooth_service.dart';
import '../services/dock_session_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// The phone-docking session screen (§8.6): pre-session dock guidance with a
/// live "is the phone close enough?" meter, then the in-session monitor.
///
/// Copy follows the overview's reliability framing: docking is the reliable
/// path, the requirements (app open, low-power off, phone on the dock) are
/// stated plainly, and a degraded link fails open — no false alarms.
class DockSessionScreen extends StatelessWidget {
  const DockSessionScreen({super.key, required this.commitment});

  final Automation commitment;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DockSessionService(),
      builder: (context, _) {
        final session = DockSessionService();
        return Scaffold(
          appBar: AppBar(title: const Text('Phone-free block')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _body(context, session),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, DockSessionService session) {
    switch (session.phase) {
      case DockPhase.idle:
        return _setupChooser(context, session);
      case DockPhase.connecting:
        return const Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.lightOrange),
            SizedBox(height: 16),
            Text('Reaching the dock…',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 14)),
          ],
        ));
      case DockPhase.positioning:
        return _positioning(context, session);
      case DockPhase.active:
        return _monitor(context, session);
      case DockPhase.ended:
        return _summary(
          context,
          session,
          icon: Icons.celebration_outlined,
          title: 'That\'s the block done.',
          body:
              'Go get your phone. Whatever you did with that time — it was '
              'yours.',
        );
      case DockPhase.linkLost:
        return _summary(
          context,
          session,
          icon: Icons.link_off,
          title: 'The link dropped',
          body:
              'The phone and dock lost each other, so the system can\'t see '
              'the phone right now. It fails open — no false alarms — but the '
              'block only really holds while the link is up. Put the phone '
              'back on the dock and start again.',
          retry: true,
        );
    }
  }

  // ── Setup-style chooser (Mode C slot, §8.6) ───────────────────────────────

  Widget _setupChooser(BuildContext context, DockSessionService session) {
    final app = context.read<AppState>();
    final anchor = BluetoothService()
        .anchors
        .where((a) => a.id == commitment.anchorId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_fmtTime(commitment.startTime)}–${_fmtTime(commitment.endTime)}',
          style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'The phone lives on its dock for this block. Not blocked — out of '
          'reach. That\'s the whole trick.',
          style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Setup style — only docking is live; two-anchor rooms slot in later.
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.lightOrange),
          ),
          child: ListTile(
            leading:
                const Icon(Icons.smartphone, color: AppTheme.lightOrange),
            title: const Text('Phone docked at an anchor',
                style: TextStyle(color: AppTheme.textWhite, fontSize: 14)),
            subtitle: Text(
              anchor == null
                  ? 'Docking anchor not paired yet — set it up in Devices.'
                  : 'Dock: ${anchor.name}',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
            ),
            trailing:
                const Icon(Icons.check_circle, color: AppTheme.lightOrange),
          ),
        ),
        const Card(
          child: ListTile(
            enabled: false,
            leading: Icon(Icons.meeting_room_outlined,
                color: AppTheme.textGrey),
            title: Text('Two-anchor room',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 14)),
            subtitle: Text('For rooms where docking isn\'t practical — '
                'coming later.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          ),
        ),
        const SizedBox(height: 20),

        // The user's side of the deal, stated plainly (§8.6 reliability).
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cardGrey,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('For this to hold, three things stay true:',
                  style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
              SizedBox(height: 8),
              Text('•  The phone sits on (or right next to) the dock',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
              Text('•  This app stays open',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
              Text('•  Low Power Mode stays off',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
              SizedBox(height: 8),
              Text(
                'If the link gets shaky anyway, nothing alarms falsely — the '
                'block just can\'t see the phone until the link is back.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
              ),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: anchor?.bleRemoteId == null
              ? null
              : () async {
                  final ok = await session.beginPositioning(
                      commitment, anchor!.bleRemoteId!);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Couldn\'t reach the dock — check it\'s powered.')));
                  }
                  // AppState is not used further here; read() avoids a
                  // rebuild dependency.
                  app.connectionChanged();
                },
          child: const Text('Connect to the dock',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // ── Positioning: live closeness meter (§8.6 step 2) ───────────────────────

  Widget _positioning(BuildContext context, DockSessionService session) {
    final dock = session.lastDock;
    final docked = dock?.docked ?? false;
    // Map RSSI (-100…-30) to 0…1 for the meter.
    final closeness =
        dock == null ? 0.0 : ((dock.rssi + 100) / 70).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Place the phone on the dock',
            style: TextStyle(
                color: AppTheme.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Center(
          child: Icon(
            docked ? Icons.task_alt : Icons.smartphone,
            color: docked ? Colors.lightGreen : AppTheme.lightOrange,
            size: 64,
          ),
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: closeness,
          minHeight: 12,
          backgroundColor: AppTheme.cardGrey,
          color: docked ? Colors.lightGreen : AppTheme.lightOrange,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 8),
        Text(
          docked
              ? 'Docked. Nice.'
              : (dock == null
                  ? 'Listening for the dock…'
                  : 'Closer — set it right on the anchor.'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: docked ? Colors.lightGreen : AppTheme.textGrey,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        if (docked)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Before you start: Low Power Mode off, app left open. Then the '
              'block runs itself.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
            ),
          ),
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
            disabledBackgroundColor: AppTheme.cardGrey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: docked ? () => session.start() : null,
          child: const Text('Start',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () => session.endSession(),
          child: const Text('Not now',
              style: TextStyle(color: AppTheme.textGrey)),
        ),
      ],
    );
  }

  // ── In-session monitor (§8.6 "during the window") ─────────────────────────

  Widget _monitor(BuildContext context, DockSessionService session) {
    final docked = session.docked;
    final rem = session.remaining;
    final h = rem.inHours;
    final m = rem.inMinutes % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: docked
              ? Colors.green.withValues(alpha: 0.12)
              : Colors.amber.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  docked ? Icons.task_alt : Icons.smartphone,
                  color: docked ? Colors.lightGreen : Colors.amber,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    docked
                        ? 'Phone-free block running — phone docked'
                        : 'Your phone left the dock',
                    style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            h > 0 ? '${h}h ${m}m left' : '${m}m left',
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 32,
                fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            docked
                ? 'Leave it be. The time is yours now.'
                : 'Picking it up counts as having it — that\'s just honest. '
                    'Set it back down whenever you\'re ready.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
          ),
        ),
        const Spacer(),
        const Text(
          'Keep this app open and the phone on its dock. A shaky link fails '
          'open — no false alarms, but no hold either.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => session.endSession(),
          child: const Text('Release the dock link',
              style: TextStyle(color: AppTheme.textGrey)),
        ),
      ],
    );
  }

  // ── Summary states ─────────────────────────────────────────────────────────

  Widget _summary(
    BuildContext context,
    DockSessionService session, {
    required IconData icon,
    required String title,
    required String body,
    bool retry = false,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, color: AppTheme.lightOrange, size: 56),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 14)),
        const SizedBox(height: 32),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () {
            session.dismiss();
            if (retry) return; // back to the chooser
            Navigator.of(context).maybePop();
          },
          child: Text(retry ? 'Try again' : 'Done',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }
}
