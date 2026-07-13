import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../models/automation_model.dart';
import '../services/commitment_policy_service.dart';
import '../services/self_binding_policy.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/policy_verdict.dart';

/// Emergency passes + self-binding settings (§8.9 item 4, §8.10): remaining
/// passes and regeneration, the spend flow (allowed on active windows —
/// deliberately), the allowance setting (raising is 24h-gated), the settle
/// window setting (growing is 24h-gated), and the audit trail.
class PassesScreen extends StatefulWidget {
  const PassesScreen({super.key});

  @override
  State<PassesScreen> createState() => _PassesScreenState();
}

class _PassesScreenState extends State<PassesScreen> {
  int _remaining = 0;
  DateTime? _regenAt;
  List<AuditEntryRow> _audit = const [];

  /// True when the numbers come from the watch's own ledger (…001B) — the
  /// authoritative source once that firmware is present.
  bool _fromWatch = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();

    // Prefer the on-watch ledger (root of trust) when it exists; the interim
    // app ledger is the fallback.
    final watchLedger = await app.readWatchPassLedger();
    int remaining;
    DateTime? regen;
    if (watchLedger != null) {
      remaining = watchLedger.remaining;
      final next = watchLedger.nextRegen;
      regen = next == null ? null : DateTime.now().add(next);
    } else {
      remaining = await app.policy.remainingPasses();
      regen = await app.integrity.nextPassRegeneratesAt(DateTime.now());
    }
    final audit = await app.integrity.auditEntries(limit: 50);
    if (!mounted) return;
    setState(() {
      _fromWatch = watchLedger != null;
      _remaining = remaining;
      _regenAt = regen;
      _audit = audit;
    });
  }

  // ── Spend flow ────────────────────────────────────────────────────────────

  Future<void> _spendFlow() async {
    final app = context.read<AppState>();
    final commitments =
        app.schedule.where((a) => !a.negate).toList();
    if (commitments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nothing to skip — no commitments are set up.')));
      return;
    }

    Automation? chosen = commitments.first;
    var day = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.darkGrey,
          title: const Text('Spend an emergency pass',
              style: TextStyle(color: AppTheme.textWhite, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A pass skips one commitment for one day, right now — even '
                'mid-window. It\'s the escape valve for the days you '
                'couldn\'t plan for.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              DropdownButton<Automation>(
                value: chosen,
                isExpanded: true,
                dropdownColor: AppTheme.cardGrey,
                style:
                    const TextStyle(color: AppTheme.textWhite, fontSize: 14),
                items: commitments
                    .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                              '${a.criteria.label} · ${_fmtTime(a.startTime)}–${_fmtTime(a.endTime)}'),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => chosen = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _dayChip(ctx, 'Today', day, DateTime.now(),
                      (d) => setDialogState(() => day = d)),
                  const SizedBox(width: 8),
                  _dayChip(
                      ctx,
                      'Tomorrow',
                      day,
                      DateTime.now().add(const Duration(days: 1)),
                      (d) => setDialogState(() => day = d)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep it',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lightOrange,
                foregroundColor: AppTheme.darkGrey,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Spend the pass'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || chosen == null || !mounted) return;
    final result = await app.spendPass(chosen!, day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? 'Pass spent — that day is yours. ${result.remaining} left this week.'
          : 'No passes left this week.'),
    ));
    await _refresh();
  }

  Widget _dayChip(BuildContext ctx, String label, DateTime current,
      DateTime value, ValueChanged<DateTime> onPick) {
    final selected = current.day == value.day && current.month == value.month;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppTheme.lightOrange,
      labelStyle: TextStyle(
          color: selected ? AppTheme.darkGrey : AppTheme.textWhite,
          fontSize: 13),
      onSelected: (_) => onPick(value),
    );
  }

  // ── Allowance & settle window ─────────────────────────────────────────────

  Future<void> _changeAllowance(int delta) async {
    final app = context.read<AppState>();
    final target = (app.policy.passAllowance + delta).clamp(0, 7);
    if (target == app.policy.passAllowance) return;
    if (delta > 0) {
      final ok = await confirmWithVerdict(
        context,
        outcome: EditOutcome(
          GateDecision.quarantine,
          ChangeClassification.loosening,
          applyAfter: DateTime.now().add(app.policy.config.loosenDelay),
        ),
        title: 'Raise the pass allowance?',
      );
      if (!ok) return;
    }
    await app.changePassAllowance(target);
    if (!mounted) return;
    if (delta > 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Queued — a bigger escape valve is an easing, so it waits a day.')));
    }
    await _refresh();
  }

  Future<void> _changeSettleWindow(int minutes) async {
    final app = context.read<AppState>();
    final current = app.policy.config.settleWindow.inMinutes;
    if (minutes > current) {
      final ok = await confirmWithVerdict(
        context,
        outcome: EditOutcome(
          GateDecision.quarantine,
          ChangeClassification.loosening,
          applyAfter: DateTime.now().add(app.policy.config.loosenDelay),
        ),
        title: 'Lengthen the free-edit window?',
      );
      if (!ok) return;
    }
    await app.changeSettleWindow(minutes);
    await _refresh();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final allowance = app.policy.passAllowance;
    final settleMin = app.policy.config.settleWindow.inMinutes;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency passes')),
      body: RefreshIndicator(
        color: AppTheme.lightOrange,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // ── Remaining passes ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < allowance; i++)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              i < _remaining
                                  ? Icons.confirmation_num
                                  : Icons.confirmation_num_outlined,
                              color: i < _remaining
                                  ? AppTheme.lightOrange
                                  : AppTheme.textGrey,
                              size: 34,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('$_remaining of $allowance passes left',
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      _regenAt == null
                          ? 'Rolling 7-day window — spend one and it comes back a week later.'
                          : 'Next pass returns ${formatWhen(_regenAt!)}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fromWatch
                          ? 'Counted by the watch itself — reinstalling the '
                              'app can\'t refill them.'
                          : 'Counted on this phone until the watch takes over.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textGrey, fontSize: 11),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.lightOrange,
                          foregroundColor: AppTheme.darkGrey,
                        ),
                        onPressed: _remaining > 0 ? _spendFlow : null,
                        child: const Text('Skip a day'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Allowance ──
            Card(
              child: ListTile(
                title: const Text('Passes per week',
                    style:
                        TextStyle(color: AppTheme.textWhite, fontSize: 14)),
                subtitle: const Text(
                    'Raising this eases your own rules — it takes a day. '
                    'Lowering it is immediate.',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: AppTheme.textGrey),
                      onPressed: () => _changeAllowance(-1),
                    ),
                    Text('$allowance',
                        style: const TextStyle(
                            color: AppTheme.textWhite, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppTheme.textGrey),
                      onPressed: () => _changeAllowance(1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Settle window ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Free-edit window',
                        style: TextStyle(
                            color: AppTheme.textWhite, fontSize: 14)),
                    const SizedBox(height: 4),
                    const Text(
                      'How long after an edit a commitment stays freely '
                      'adjustable before it settles. Lengthening it waits a '
                      'day; shortening is immediate.',
                      style:
                          TextStyle(color: AppTheme.textGrey, fontSize: 12),
                    ),
                    Slider(
                      value: settleMin.toDouble(),
                      min: 30,
                      max: 240,
                      divisions: 7,
                      activeColor: AppTheme.lightOrange,
                      label: '$settleMin min',
                      onChanged: null, // display only; commit via buttons
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$settleMin minutes',
                            style: const TextStyle(
                                color: AppTheme.textWhite, fontSize: 13)),
                        Row(
                          children: [
                            TextButton(
                              onPressed: settleMin > 30
                                  ? () =>
                                      _changeSettleWindow(settleMin - 30)
                                  : null,
                              child: const Text('−30 min'),
                            ),
                            TextButton(
                              onPressed: settleMin < 240
                                  ? () =>
                                      _changeSettleWindow(settleMin + 30)
                                  : null,
                              child: const Text('+30 min'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Audit trail ──
            const Text('History',
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_audit.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nothing yet.',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
              )
            else
              for (final e in _audit)
                ListTile(
                  dense: true,
                  leading: Icon(_auditIcon(e.category),
                      color: AppTheme.textGrey, size: 18),
                  title: Text(e.detail.isEmpty ? e.category : e.detail,
                      style: const TextStyle(
                          color: AppTheme.textWhite, fontSize: 13)),
                  subtitle: Text(
                    '${e.timestamp.year}-${e.timestamp.month.toString().padLeft(2, '0')}-${e.timestamp.day.toString().padLeft(2, '0')} '
                    '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: 11),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  IconData _auditIcon(String category) {
    switch (category) {
      case 'pass_spent':
        return Icons.confirmation_num;
      case 'loosening_queued':
        return Icons.hourglass_top;
      case 'loosening_promoted':
        return Icons.schedule_send;
      case 'loosening_cancelled':
        return Icons.undo;
      case 'tightening_applied':
        return Icons.lock_outline;
      default:
        return Icons.circle_outlined;
    }
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }
}

