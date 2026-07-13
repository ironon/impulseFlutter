import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/bluetooth_device_model.dart';
import '../services/anchor_telemetry_service.dart';
import '../theme/app_theme.dart';

/// Guided walk-around calibration (§8.5): the user moves around near the
/// anchor while it collects high-confidence training samples (this is what
/// self-supervision does, sped up). A donut progress ring fills as real
/// movement accumulates, with the live Prox Score shown inside so the user
/// sees proof it's working rather than just a countdown.
///
/// Progress driver (best-effort per spec): the phone's accelerometer
/// accumulates "movement time" toward [targetMovement]; where the sensor is
/// unavailable the ring degrades to plain elapsed time.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.anchor});

  final BluetoothDeviceModel anchor;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const targetMovement = Duration(seconds: 45);
  static const _movementThreshold = 0.8; // m/s² of user acceleration
  static const _tick = Duration(milliseconds: 250);

  AnchorTelemetrySession? _session;
  StreamSubscription<ProxScoreReading>? _proxSub;
  StreamSubscription<UserAccelerometerEvent>? _imuSub;
  Timer? _ticker;

  bool _connecting = true;
  bool _connected = false;
  bool _sensorAvailable = true;
  bool _moving = false;
  Duration _accumulated = Duration.zero;
  ProxScoreReading? _prox;
  DateTime _lastImuEvent = DateTime.now();

  bool get _done => _accumulated >= targetMovement;
  double get _progress =>
      (_accumulated.inMilliseconds / targetMovement.inMilliseconds)
          .clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Live prox feedback (read-only telemetry, §8.5).
    if (widget.anchor.bleRemoteId != null) {
      final session = AnchorTelemetrySession(widget.anchor.bleRemoteId!);
      final ok = await session.connect();
      if (!mounted) {
        session.dispose();
        return;
      }
      if (ok) {
        _session = session;
        _proxSub = session.proxStream.listen((r) {
          if (mounted) setState(() => _prox = r);
        });
      }
      setState(() {
        _connecting = false;
        _connected = ok;
      });
    } else {
      setState(() {
        _connecting = false;
        _connected = false;
      });
    }

    // Movement driver: user-acceleration magnitude above threshold = moving.
    try {
      _imuSub = userAccelerometerEventStream().listen((e) {
        final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
        _moving = mag > _movementThreshold;
        _lastImuEvent = DateTime.now();
      }, onError: (_) {
        _sensorAvailable = false;
      });
    } catch (_) {
      _sensorAvailable = false;
    }

    _ticker = Timer.periodic(_tick, (_) {
      if (_done) {
        _ticker?.cancel();
        setState(() {});
        return;
      }
      // No IMU events for 2 s ⇒ treat the sensor as unavailable (desktop /
      // emulator) and fall back to plain elapsed time.
      final sensorLive = _sensorAvailable &&
          DateTime.now().difference(_lastImuEvent) < const Duration(seconds: 2);
      if (!sensorLive || _moving) {
        setState(() => _accumulated += _tick);
      } else {
        setState(() {}); // keep the score fresh
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _proxSub?.cancel();
    _imuSub?.cancel();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calibrate ${widget.anchor.name}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _done
                    ? 'Done — this anchor has a feel for its room now.'
                    : 'Walk around the room, phone in hand',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _done
                    ? 'It keeps learning on its own from here.'
                    : 'Wander near the anchor — cross the room, turn around, '
                        'come back. The anchor is learning what "here" looks '
                        'like.',
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
                      progress: _progress,
                      color:
                          _done ? Colors.lightGreen : AppTheme.lightOrange,
                      track: AppTheme.cardGrey,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _connecting
                                ? '…'
                                : (_prox == null
                                    ? '—'
                                    : '${_prox!.score}'),
                            style: const TextStyle(
                                color: AppTheme.textWhite,
                                fontSize: 44,
                                fontWeight: FontWeight.bold),
                          ),
                          const Text('live closeness score',
                              style: TextStyle(
                                  color: AppTheme.textGrey, fontSize: 11)),
                          if (_prox?.fingerprintActive == true)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text('fingerprint active ✓',
                                  style: TextStyle(
                                      color: Colors.lightGreen,
                                      fontSize: 11)),
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
                  _done
                      ? ''
                      : '${(_progress * 100).round()}% · '
                          '${(targetMovement - _accumulated).inSeconds}s of movement to go',
                  style:
                      const TextStyle(color: AppTheme.textGrey, fontSize: 12),
                ),
              ),
              if (!_connected && !_connecting)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Couldn\'t reach the anchor for a live score — the '
                    'walk-around still helps it learn.',
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
                onPressed:
                    _done ? () => Navigator.of(context).maybePop() : null,
                child: Text(_done ? 'Done' : 'Keep moving…',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
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
