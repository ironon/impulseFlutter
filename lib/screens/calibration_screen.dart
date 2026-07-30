import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/bluetooth_device_model.dart';
import '../services/calibration_store.dart';
import '../services/watch_service.dart';
import '../theme/app_theme.dart';

/// App-guided calibration-v2 (firmware §4.10.7 + CALIBRATION_V2_DESIGN.md). The
/// user physically *demonstrates* the near-zone in two labeled phases and the
/// anchor learns its own decision threshold from the score gap between them:
///
///   INSIDE   — roam the area you want counted as "near" (small for a desk, the
///              whole room for a gym). Every sample trains the fingerprint.
///   EDGE     — step just past your tolerance and stand there / walk the border.
///              These samples only calibrate the cutoff; they don't train.
///   FINALIZE — the anchor computes + persists `near_threshold` and reports it.
///
/// The *watch* does the RF work (it authors real-MAC vectors the anchor can
/// train on — iOS never exposes on-air MACs, so the phone can't). The phone
/// drives the phases over the watch link. This firmware can't central-connect to
/// the anchor while holding the phone link (NimBLE crash), so each phase runs
/// while the phone is DISCONNECTED (Option A): the app writes the phase START,
/// drops the watch link, times the walk, then reconnects to advance.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.anchor});

  final BluetoothDeviceModel anchor;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

/// User-facing tolerance framing (decision 8) — guidance only, no number is sent
/// to firmware. It changes the instructions and the suggested INSIDE duration.
enum _Tolerance { tight, roomy }

enum _Step {
  intro, // choose tolerance framing, read what to do
  insideBurst, // phone disconnected, user roams the near-zone
  edgePrompt, // reconnected; explain the edge step
  edgeBurst, // phone disconnected, user stands just past the limit
  finalizePrompt, // reconnected; ready to compute the threshold
  finalizeWait, // phone disconnected, watch queries the anchor to finalize
  done, // result shown
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  _Tolerance _tolerance = _Tolerance.tight;
  _Step _step = _Step.intro;
  String? _error; // non-null → fatal problem, show the error panel
  bool _busy = false; // a reconnect/handshake is in flight (buttons disabled)

  int _insideAccepted = 0; // samples the anchor trained on during INSIDE
  CalibrationResult? _result; // FINALIZE outcome

  int _elapsedS = 0;
  int _phaseDurationS = 0;
  Timer? _ticker;

  /// The watch device, captured so we can reconnect after each disconnected
  /// phase (Option A, §8.5).
  fbp.BluetoothDevice? _watchDevice;

  int get _insideDurationS => _tolerance == _Tolerance.tight ? 45 : 75;
  static const _edgeDurationS = 30;

  bool get _burstActive => _step == _Step.insideBurst || _step == _Step.edgeBurst;
  double get _ringProgress => _phaseDurationS == 0
      ? 0.0
      : (_elapsedS / _phaseDurationS).clamp(0.0, 1.0);
  int get _remainingS => (_phaseDurationS - _elapsedS).clamp(0, _phaseDurationS);

  @override
  void dispose() {
    _ticker?.cancel();
    // Bailed out mid-burst → best-effort reconnect + tell the watch to stop so
    // it doesn't keep bursting and the app link is restored.
    if (_burstActive || _step == _Step.finalizeWait) {
      final ws = WatchService();
      final dev = _watchDevice;
      final uuid = widget.anchor.id;
      unawaited(() async {
        try {
          if (dev != null && !ws.isConnected) await ws.connect(dev);
          await ws.abortCalibration(uuid);
          await ws.stopCalibration();
        } catch (_) {}
      }());
    }
    super.dispose();
  }

  // ── Pre-flight ────────────────────────────────────────────────────────────

  String? _preflight(WatchService ws) {
    if (!ws.isConnected) {
      return "Your watch isn't connected. Bring it near your phone, open the "
          'Impulse app connection, and try again.';
    }
    if (!ws.hasCalibrationCharacteristic) {
      return "This watch's firmware doesn't support guided calibration yet. "
          'Update the watch and try again.';
    }
    if (!_looksLikeUuid(widget.anchor.id)) {
      return "Couldn't identify this anchor. Re-scan for it on the Devices "
          'screen and try again.';
    }
    return null;
  }

  // ── Phase drivers ─────────────────────────────────────────────────────────

  /// Kick off the INSIDE phase from the intro screen.
  Future<void> _startInside() async {
    final ws = WatchService();
    final err = _preflight(ws);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _watchDevice = ws.device;
    await _runBurst(
      phase: CalibrationPhase.inside,
      durationS: _insideDurationS,
      burstStep: _Step.insideBurst,
      onComplete: (progress) {
        _insideAccepted = progress?.accepted ?? 0;
        setState(() => _step = _Step.edgePrompt);
      },
    );
  }

  /// Kick off the EDGE phase from the edge prompt.
  Future<void> _startEdge() async {
    await _runBurst(
      phase: CalibrationPhase.edge,
      durationS: _edgeDurationS,
      burstStep: _Step.edgeBurst,
      onComplete: (_) => setState(() => _step = _Step.finalizePrompt),
    );
  }

  /// Shared burst driver: write the phase START, disconnect, run the walk timer,
  /// then reconnect and read the progress, handing it to [onComplete].
  Future<void> _runBurst({
    required CalibrationPhase phase,
    required int durationS,
    required _Step burstStep,
    required void Function(CalibrationProgress?) onComplete,
  }) async {
    final ws = WatchService();
    setState(() => _busy = true);
    try {
      await ws.startCalibration(widget.anchor.id,
          durationS: durationS, phase: phase);
      try {
        await ws.disconnect();
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start calibration: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _step = burstStep;
      _busy = false;
      _elapsedS = 0;
      _phaseDurationS = durationS;
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() => _elapsedS++);
      if (_elapsedS >= _phaseDurationS) {
        _ticker?.cancel();
        // Reconnect and CONFIRM the calibration characteristic rediscovered before
        // advancing. The old path swallowed reconnect failures and advanced anyway,
        // so the next phase button hit a null characteristic and threw "watch
        // doesn't support this feature". If we can't get a good link back, stop and
        // show a retryable error instead of falling through into a broken state.
        final ok = await _reconnectAndVerify();
        if (!mounted) return;
        if (!ok) {
          setState(() {
            _busy = false;
            _error =
                'Lost the connection to your watch after the walk. Bring the '
                'watch close to your phone, then tap Back and start calibration '
                'again.';
          });
          return;
        }
        final progress = await WatchService().readCalibrationProgress();
        if (!mounted) return;
        onComplete(progress);
      }
    });
  }

  /// Reconnect the watch link after a disconnected burst and CONFIRM the
  /// calibration characteristic is actually present again before letting the flow
  /// advance. This is the fix for the "watch doesn't support this feature" error
  /// on a slow phase advance: the watch could drop to light sleep in the reconnect
  /// gap, the app would reconnect onto a degraded link, fail to rediscover the
  /// characteristic, and silently advance — then the next phase button threw.
  ///
  /// The firmware now holds the watch awake/connectable across this gap
  /// (inter-phase awake window), so a clean rediscovery normally succeeds; we still
  /// retry a few times and only report success once [hasCalibrationCharacteristic]
  /// is true. Returns false if we never get a good link back.
  Future<bool> _reconnectAndVerify() async {
    final ws = WatchService();
    final dev = _watchDevice;
    if (dev == null) return false;
    setState(() => _busy = true);
    // Guard margin: let the watch's last anchor query and its radio settle before
    // we bring the phone link back up, so the reconnect doesn't collide with watch
    // activity at the phase boundary (pairs with the firmware quiet-tail).
    await Future<void>.delayed(const Duration(seconds: 2));
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!mounted) return false;
      try {
        if (!ws.isConnected) await ws.connect(dev);
        if (ws.hasCalibrationCharacteristic) {
          if (mounted) setState(() => _busy = false);
          return true;
        }
        // Connected but the characteristic didn't rediscover — drop and retry; a
        // fresh service discovery on the next connect usually resolves it.
        await ws.disconnect();
      } catch (_) {
        try {
          await ws.disconnect();
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted) setState(() => _busy = false);
    return false;
  }

  /// Reconnect the watch link and read the latest progress frame.
  Future<CalibrationProgress?> _reconnectAndRead() async {
    final ws = WatchService();
    final dev = _watchDevice;
    setState(() => _busy = true);
    CalibrationProgress? progress;
    try {
      if (dev != null && !ws.isConnected) await ws.connect(dev);
      progress = await ws.readCalibrationProgress();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
    return progress;
  }

  /// FINALIZE: request the threshold computation, disconnect so the watch can
  /// reach the anchor, then poll (reconnect + read) until the result arrives.
  Future<void> _finalize() async {
    final ws = WatchService();
    setState(() {
      _busy = true;
      _step = _Step.finalizeWait;
    });
    try {
      await ws.finalizeCalibration(widget.anchor.id);
      try {
        await ws.disconnect();
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not finalize: $e');
      return;
    }

    // The watch needs the phone disconnected to connect to the anchor. Give it a
    // few seconds, then poll for the result frame a handful of times.
    CalibrationResult? result;
    for (var attempt = 0; attempt < 6 && result == null; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      // Reconnect briefly to read, then drop again so a retry can let the watch
      // work while disconnected.
      final progress = await _reconnectAndRead();
      result = progress?.result;
      if (result == null) {
        try {
          await WatchService().disconnect();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    if (result == null) {
      setState(() => _error =
          "The anchor didn't report a result. Make sure your watch stayed near "
          'the anchor, then try calibrating again.');
      return;
    }

    // Persist for the Devices-screen "calibrated ✓" badge, and close the session.
    try {
      final store = CalibrationStore();
      await store.load();
      await store.record(widget.anchor.id,
          nearThreshold: result.nearThreshold,
          insideN: result.insideN,
          edgeN: result.edgeN,
          confidence: result.confidence);
    } catch (_) {}
    try {
      await WatchService().stopCalibration();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
      _step = _Step.done;
    });
  }

  /// Restart the whole flow (low-confidence redo).
  void _redo() {
    setState(() {
      _step = _Step.intro;
      _error = null;
      _result = null;
      _insideAccepted = 0;
      _elapsedS = 0;
      _phaseDurationS = 0;
    });
  }

  static bool _looksLikeUuid(String s) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
              r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(s);

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calibrate ${widget.anchor.name}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _error != null ? _buildError() : _buildStep(),
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
        _primaryButton('Back', () => Navigator.of(context).maybePop()),
      ],
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.intro:
        return _buildIntro();
      case _Step.insideBurst:
      case _Step.edgeBurst:
        return _buildBurst();
      case _Step.edgePrompt:
        return _buildEdgePrompt();
      case _Step.finalizePrompt:
        return _buildFinalizePrompt();
      case _Step.finalizeWait:
        return _buildFinalizeWait();
      case _Step.done:
        return _buildDone();
    }
  }

  // Step 1 — intro + tolerance framing.
  Widget _buildIntro() {
    final tight = _tolerance == _Tolerance.tight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Show this anchor your near-zone',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          "You'll walk the area you want counted as \"near\", then step just "
          'past it. The anchor learns the boundary from what you demonstrate — '
          'so a desk stays tight and a whole room stays roomy.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
        ),
        const SizedBox(height: 24),
        const Text('How big is this zone?',
            style: TextStyle(
                color: AppTheme.textWhite,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _toleranceCard(
          selected: tight,
          title: 'Tight — desk / nightstand',
          body: 'Stay within arm’s reach of the anchor.',
          onTap: () => setState(() => _tolerance = _Tolerance.tight),
        ),
        const SizedBox(height: 10),
        _toleranceCard(
          selected: !tight,
          title: 'Roomy — gym / room',
          body: 'Cover the whole space you want counted.',
          onTap: () => setState(() => _tolerance = _Tolerance.roomy),
        ),
        const Spacer(),
        _primaryButton(_busy ? 'Starting…' : 'Start', _busy ? null : _startInside),
      ],
    );
  }

  Widget _toleranceCard({
    required bool selected,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardGrey,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.lightOrange : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppTheme.lightOrange : AppTheme.textGrey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          color: AppTheme.textGrey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Steps 2 & 4 — a running burst (phone disconnected, timed walk).
  Widget _buildBurst() {
    final inside = _step == _Step.insideBurst;
    final title = inside ? 'Move through your near-zone' : 'Step just past your limit';
    final sub = inside
        ? (_tolerance == _Tolerance.tight
            ? 'Stay within arm’s reach — lean in, sit, shift around the anchor. '
                'Keep your watch on and the app open.'
            : 'Wander the whole space you want counted — cross the room, turn '
                'around, come back. Keep your watch on and the app open.')
        : 'Walk to just outside your zone and stay there — pace the boundary a '
            'little. This teaches the anchor where "near" ends.';
    return _ringScaffold(
      title: title,
      subtitle: sub,
      centreBig: '${_remainingS}s',
      centreSub: 'time left',
      progress: _ringProgress,
      color: inside ? AppTheme.lightOrange : Colors.amber,
      footer: _stepDots(inside ? 1 : 2),
    );
  }

  // Step 3 — reconnected between INSIDE and EDGE.
  Widget _buildEdgePrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.check_circle, color: Colors.lightGreen, size: 44),
        const SizedBox(height: 12),
        Text(
          'Near-zone captured'
          '${_insideAccepted > 0 ? ' · $_insideAccepted samples' : ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Now the edge. When you tap continue, walk to just OUTSIDE the zone — '
          'the closest spot that should count as "away" — and stand there while '
          'the ring fills.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
        ),
        const Spacer(),
        _stepDots(1),
        const SizedBox(height: 16),
        _primaryButton(_busy ? 'Starting…' : 'Continue to the edge',
            _busy ? null : _startEdge),
      ],
    );
  }

  // Step 5 — reconnected after EDGE, ready to finalize.
  Widget _buildFinalizePrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.tune, color: AppTheme.lightOrange, size: 44),
        const SizedBox(height: 12),
        const Text(
          'Ready to set the zone',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'The anchor will compute its near/away boundary from what you showed '
          'it. Keep your watch near the anchor — this takes a few seconds while '
          'your phone steps back.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
        ),
        const Spacer(),
        _stepDots(2),
        const SizedBox(height: 16),
        _primaryButton('Set the zone', _busy ? null : _finalize),
      ],
    );
  }

  // Step 6 — waiting for the anchor to compute + report the threshold.
  Widget _buildFinalizeWait() {
    return _ringScaffold(
      title: 'Setting the zone…',
      subtitle: 'Your watch is asking the anchor to work out its boundary. Keep '
          'the watch near the anchor and the app open.',
      centreBig: '…',
      centreSub: 'computing',
      progress: null, // indeterminate
      color: AppTheme.lightOrange,
      footer: _stepDots(2),
    );
  }

  // Step 7 — result.
  /// A calibration can fail two ways and they need opposite advice. Sample
  /// starvation means the demonstration was fine and simply too short — the
  /// firmware never got as far as comparing the distributions, so telling the
  /// user their walk was ambiguous would send them to fix something that isn't
  /// broken. Starvation is far more likely on the EDGE leg: further from the
  /// anchor each reading takes seconds longer to collect.
  String _failureTitle(CalibrationResult r) {
    switch (r.failure) {
      case CalibrationFailure.tooFewSamples:
        return 'Not enough readings';
      case CalibrationFailure.overlap:
      case null:
        return "Couldn't separate near from edge";
    }
  }

  String _failureBody(CalibrationResult r) {
    switch (r.failure) {
      case CalibrationFailure.tooFewSamples:
        final short = r.edgeStarved && r.insideStarved
            ? 'Both parts'
            : (r.edgeStarved ? 'The edge part' : 'The inside part');
        return '$short came up short — ${r.insideN} inside · ${r.edgeN} edge, and '
            'at least ${CalibrationResult.minSamplesPerLeg} of each are needed. '
            'Your readings looked fine, there just were not enough of them. Try '
            'again and stay put a little longer at each step, especially the '
            'edge spot — readings come in more slowly further from the anchor.';
      case CalibrationFailure.overlap:
      case null:
        return 'The inside and edge readings overlapped, so this anchor kept '
            'the default boundary. Try again: make the inside walk and the '
            'edge spot clearly different distances.';
    }
  }

  Widget _buildDone() {
    final r = _result!;
    final confident = r.isConfident;
    final zoneWord = _tolerance == _Tolerance.tight ? 'desk zone' : 'room zone';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Icon(confident ? Icons.check_circle : Icons.warning_amber_rounded,
            color: confident ? Colors.lightGreen : Colors.amber, size: 52),
        const SizedBox(height: 14),
        Text(
          confident ? 'Your $zoneWord is set' : _failureTitle(r),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          confident
              ? '${r.insideN} inside · ${r.edgeN} edge samples · '
                  'threshold ${r.nearThreshold}'
              : _failureBody(r),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 14),
        ),
        const SizedBox(height: 8),
        if (confident)
          const Text(
            'It keeps refining itself from here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
          ),
        const Spacer(),
        if (!confident) ...[
          _primaryButton(
              r.failure == CalibrationFailure.tooFewSamples
                  ? 'Try again'
                  : 'Redo calibration',
              _redo),
          const SizedBox(height: 10),
          _secondaryButton('Keep default', () => Navigator.of(context).maybePop()),
        ] else ...[
          _primaryButton('Done', () => Navigator.of(context).maybePop()),
          const SizedBox(height: 10),
          _secondaryButton('Redo', _redo),
        ],
      ],
    );
  }

  // ── Small UI helpers ───────────────────────────────────────────────────────

  Widget _ringScaffold({
    required String title,
    required String subtitle,
    required String centreBig,
    required String centreSub,
    required double? progress,
    required Color color,
    Widget? footer,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
        const Spacer(),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: progress == null
                ? _indeterminateRing(color, centreBig, centreSub)
                : CustomPaint(
                    painter: _DonutPainter(
                      progress: progress,
                      color: color,
                      track: AppTheme.cardGrey,
                    ),
                    child: _ringCentre(centreBig, centreSub),
                  ),
          ),
        ),
        const Spacer(),
        ?footer,
        const SizedBox(height: 16),
        _secondaryButton('Stop', () async {
          _ticker?.cancel();
          final ws = WatchService();
          try {
            if (_watchDevice != null && !ws.isConnected) {
              await ws.connect(_watchDevice!);
            }
            await ws.abortCalibration(widget.anchor.id);
            await ws.stopCalibration();
          } catch (_) {}
          if (mounted) Navigator.of(context).maybePop();
        }),
      ],
    );
  }

  Widget _indeterminateRing(Color color, String big, String sub) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 220,
          height: 220,
          child: CircularProgressIndicator(
            strokeWidth: 16,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            backgroundColor: AppTheme.cardGrey,
          ),
        ),
        _ringCentre(big, sub),
      ],
    );
  }

  Widget _ringCentre(String big, String sub) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(big,
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 44,
                  fontWeight: FontWeight.bold)),
          Text(sub,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
        ],
      ),
    );
  }

  /// Two-dot progress indicator (INSIDE = dot 1, EDGE = dot 2).
  Widget _stepDots(int active) {
    Widget dot(int n) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: n <= active ? AppTheme.lightOrange : AppTheme.cardGrey,
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [dot(1), dot(2)],
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.lightOrange,
        foregroundColor: AppTheme.darkGrey,
        disabledBackgroundColor: AppTheme.cardGrey,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _secondaryButton(String label, VoidCallback? onPressed) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(color: AppTheme.textGrey)),
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
