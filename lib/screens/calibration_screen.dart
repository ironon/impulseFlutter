import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

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

enum _Phase { starting, bursting, finishing, done }

class _CalibrationScreenState extends State<CalibrationScreen> {
  /// Requested burst length; the watch clamps to its own bounds.
  static const _durationS = 90;

  String? _error; // non-null → fatal pre-flight problem, nothing was started
  _Phase _phase = _Phase.starting;
  int _elapsedS = 0;
  Timer? _ticker;

  /// The watch device, captured before we disconnect so we can reconnect at the
  /// end to read the result (Option A, §8.5).
  fbp.BluetoothDevice? _watchDevice;

  /// Final progress frame read after reconnecting; null until the burst ends.
  CalibrationProgress? _result;

  bool get _finished => _phase == _Phase.done;
  // Option A: the app is disconnected during the burst, so there's no live
  // accepted-sample count — the ring fills by elapsed walking time (§8.5's
  // documented fallback), and the real learned-count is read at the end.
  double get _ringProgress =>
      _finished ? 1.0 : (_elapsedS / _durationS).clamp(0.0, 1.0);
  int get _remainingS => (_durationS - _elapsedS).clamp(0, _durationS);

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

    _watchDevice = ws.device; // capture for the end-of-burst reconnect

    try {
      await ws.startCalibration(widget.anchor.id, durationS: _durationS);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start calibration: $e');
      return;
    }

    // Option A (§8.5): this watch firmware can't do a central connect to the
    // anchor while holding the phone (peripheral) link — it crashes NimBLE. So
    // the watch only bursts while the phone is DISCONNECTED. Drop the watch link
    // for the burst and reconnect at the end to read the result.
    try { await ws.disconnect(); } catch (_) {}

    if (!mounted) return;
    setState(() { _phase = _Phase.bursting; _elapsedS = 0; });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedS++);
      if (_elapsedS >= _durationS) _finishBurst();
    });
  }

  /// Burst duration elapsed → reconnect, read the learned-sample count, and
  /// restore the app's watch link.
  Future<void> _finishBurst() async {
    _ticker?.cancel();
    if (!mounted) return;
    setState(() => _phase = _Phase.finishing);

    final ws = WatchService();
    CalibrationProgress? result;
    final dev = _watchDevice;
    if (dev != null) {
      try {
        await ws.connect(dev);
        result = await ws.readCalibrationProgress();
        await ws.stopCalibration(); // ensure the session is closed on the watch
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() { _result = result; _phase = _Phase.done; });
  }

  /// User tapped Stop mid-burst: reconnect, tell the watch to stop, leave.
  Future<void> _stopEarly() async {
    _ticker?.cancel();
    final ws = WatchService();
    final dev = _watchDevice;
    try {
      if (dev != null && !ws.isConnected) await ws.connect(dev);
      await ws.stopCalibration();
    } catch (_) {}
  }

  static bool _looksLikeUuid(String s) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
              r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(s);

  @override
  void dispose() {
    _ticker?.cancel();
    // Bailed out mid-burst → best-effort reconnect + stop so the watch doesn't
    // keep bursting and the app link is restored. Fire-and-forget (no `this`).
    if (_phase == _Phase.bursting) {
      final ws = WatchService();
      final dev = _watchDevice;
      unawaited(() async {
        try {
          if (dev != null && !ws.isConnected) await ws.connect(dev);
          await ws.stopCalibration();
        } catch (_) {}
      }());
    }
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
    final finishing = _phase == _Phase.finishing;
    final learned = _result?.accepted;

    // Donut centre + caption per phase. During the burst the phone is
    // disconnected from the watch, so we show a walking-time countdown rather
    // than a live score (Option A, §8.5).
    final String centreBig;
    final String centreSub;
    if (_finished) {
      centreBig = learned != null ? '$learned' : '✓';
      centreSub = learned != null ? 'samples learned' : 'calibrated';
    } else if (finishing) {
      centreBig = '…';
      centreSub = 'wrapping up';
    } else {
      centreBig = '${_remainingS}s';
      centreSub = 'walking time left';
    }

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
              : finishing
                  ? 'Reconnecting to your watch to read the results…'
                  : 'Keep your watch on and wander near the anchor — cross the '
                      'room, turn around, come back. Keep the app open; your '
                      'watch works with the anchor directly during this.',
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
                      centreBig,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: 44,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(centreSub,
                        style: const TextStyle(
                            color: AppTheme.textGrey, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: finishing
              ? null
              : () async {
                  if (!_finished) await _stopEarly();
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
