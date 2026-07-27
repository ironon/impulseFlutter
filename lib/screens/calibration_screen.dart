import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/bluetooth_device_model.dart';
import '../services/watch_service.dart';
import '../theme/app_theme.dart';

/// App-guided calibration (firmware §4.10.7). The *watch* — not the phone —
/// does the work: while the user walks around near the anchor, the watch bursts
/// its real-MAC scan vectors at that anchor so the anchor's fingerprint
/// (§4.10.4) fills in seconds instead of days. The phone only kicks off the
/// burst over the watch link and renders the progress the watch reports.
///
/// Why not the phone: the fingerprint keys on raw on-air MAC/BSSID addresses,
/// which iOS never exposes (and which BLE-privacy peers rotate), so a
/// phone-scanned fingerprint could not align with what the anchor/watch see.
/// The donut therefore fills by *accepted training samples* the anchor actually
/// folded in — real learning — not by an elapsed-time animation.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.anchor});

  final BluetoothDeviceModel anchor;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  /// Requested burst length; the watch clamps to its own bounds.
  static const _durationS = 90;

  /// Accepted-sample count at which the ring reads "full". A near, unambiguous
  /// walk-around reaches this well within [_durationS]; the anchor keeps
  /// learning on its own afterwards regardless.
  static const _targetAccepted = 25;

  StreamSubscription<CalibrationProgress>? _sub;

  CalibrationProgress? _progress;
  String? _error; // non-null → fatal pre-flight problem, nothing was started
  bool _started = false;

  bool get _finished =>
      _progress != null &&
      (_progress!.state == CalibrationState.done ||
          _progress!.state == CalibrationState.aborted ||
          _progress!.accepted >= _targetAccepted);

  double get _ringProgress => _progress == null
      ? 0.0
      : (_progress!.accepted / _targetAccepted).clamp(0.0, 1.0);

  /// Watch is querying but the anchor isn't accepting samples yet — usually the
  /// user needs to move closer / into the room.
  bool get _stalled =>
      !_finished &&
      _progress != null &&
      _progress!.queries >= 5 &&
      _progress!.accepted == 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ws = WatchService();

    if (!ws.isConnected) {
      setState(() => _error =
          "Your watch isn't connected. Bring it near your phone, open the "
          'Impulse app connection, and try again.');
      return;
    }
    if (!ws.hasCalibrationCharacteristic) {
      setState(() => _error =
          "This watch's firmware doesn't support guided calibration yet. "
          'Update the watch and try again.');
      return;
    }
    if (!_looksLikeUuid(widget.anchor.id)) {
      setState(() => _error =
          "Couldn't identify this anchor. Re-scan for it on the Devices "
          'screen and try again.');
      return;
    }

    _sub = ws.calibrationStream.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
    });

    try {
      await ws.startCalibration(widget.anchor.id, durationS: _durationS);
      if (mounted) setState(() => _started = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not start calibration: $e');
      }
    }
  }

  static bool _looksLikeUuid(String s) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
              r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(s);

  @override
  void dispose() {
    _sub?.cancel();
    // Best-effort stop so the watch doesn't keep bursting after we leave.
    if (_started && !_finished) WatchService().stopCalibration();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calibrate ${widget.anchor.name}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _error != null ? _buildError() : _buildRunning(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline, color: Colors.amber, size: 48),
        const SizedBox(height: 16),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 15),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Back', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    final p = _progress;
    final scoreLabel = p == null ? '…' : '${p.lastScore}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _finished
              ? 'Done — this anchor has a feel for its room now.'
              : 'Walk around the room, watch on your wrist',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _finished
              ? 'It keeps learning on its own from here.'
              : 'Keep your watch on and wander near the anchor — cross the '
                  'room, turn around, come back. Your watch is teaching the '
                  'anchor what "here" looks like.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
        ),
        const Spacer(),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: CustomPaint(
              painter: _DonutPainter(
                progress: _ringProgress,
                color: _finished ? Colors.lightGreen : AppTheme.lightOrange,
                track: AppTheme.cardGrey,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      scoreLabel,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: 44,
                          fontWeight: FontWeight.bold),
                    ),
                    const Text('live closeness score',
                        style:
                            TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                    if (p?.fingerprintActive == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('fingerprint active ✓',
                            style: TextStyle(
                                color: Colors.lightGreen, fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _finished
                ? '${p?.accepted ?? 0} samples learned'
                : p == null
                    ? 'Starting…'
                    : '${p.accepted}/$_targetAccepted samples learned · '
                        '${p.remainingS}s left',
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
          ),
        ),
        if (_stalled)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Move closer to the anchor — your watch is checking in but '
              "isn't near enough for it to learn yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ),
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () async {
            if (!_finished) await WatchService().stopCalibration();
            if (mounted) Navigator.of(context).maybePop();
          },
          child: Text(_finished ? 'Done' : 'Stop',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    const stroke = 16.0;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.color != color;
}
