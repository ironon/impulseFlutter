// Shared presentation of self-binding verdicts (spec v2 §8.9 item 5).
//
// Three pieces: the wording functions, the confirm dialog every edit path shows
// BEFORE committing, and the amber pending badge. Keeping the copy in one file is
// what stops two screens describing the same verdict differently — and the voice
// rule ("no earlier than", never "at") is load-bearing, because promotion waits for
// a push opportunity and can only ever be later than nominal.
//
// `formatWhen` compares calendar days (not instants) so "today"/"tomorrow" stay
// correct across midnight.

import 'package:flutter/material.dart';

import '../services/commitment_policy_service.dart';
import '../services/self_binding_policy.dart';
import '../theme/app_theme.dart';

/// Voice-guide-compliant phrasing of a gate verdict (§8.9 item 5).
/// One-line headline for a gate verdict: "Applies now", "Applies now — still in
/// your free-edit window", or "Takes effect no earlier than …". `applyAfter` is
/// non-null exactly when the outcome is quarantined, so the `!` is safe here.
String verdictHeadline(EditOutcome outcome) {
  if (!outcome.queued) {
    return outcome.classification == ChangeClassification.tightening
        ? 'Applies now'
        : 'Applies now — still in your free-edit window';
  }
  return 'Takes effect no earlier than ${formatWhen(outcome.applyAfter!)}';
}

/// The explanatory sentence under the headline. Deliberately states the *reason*
/// (harder is always immediate; a settled easing waits; the old rule keeps holding),
/// because the verdict is the moment the user learns the rule.
String verdictBody(EditOutcome outcome) {
  if (!outcome.queued) {
    return outcome.classification == ChangeClassification.tightening
        ? 'Binding yourself harder is always immediate.'
        : 'This commitment hasn\'t settled yet, so you can still shape it freely.';
  }
  return 'This eases a commitment past-you already settled. The current rule '
      'keeps holding the line until then — that\'s the deal you made with '
      'yourself.';
}

/// Human date/time for a pending promotion: "today 9:00 AM", "tomorrow 9:00 AM",
/// or "Thu 9:00 AM". Compares calendar days, not instants, so a time just after
/// midnight still reads "tomorrow" for the previous day.
String formatWhen(DateTime t) {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final day = DateTime(t.year, t.month, t.day);
  final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  final time = '$hh:$mm $ampm';
  if (day == DateTime(now.year, now.month, now.day)) return 'today $time';
  if (day == tomorrow) return 'tomorrow $time';
  const wd = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[t.weekday]} $time';
}

/// Shows the preview verdict BEFORE a change is committed. Returns true when
/// the user confirms.
Future<bool> confirmWithVerdict(
  BuildContext context, {
  required EditOutcome outcome,
  String? title,
}) async {
  final queued = outcome.queued;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.darkGrey,
      title: Text(title ?? (queued ? 'This change will wait' : 'Ready to save'),
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                queued ? Icons.hourglass_top : Icons.check_circle_outline,
                color: queued ? Colors.amber : Colors.lightGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(verdictHeadline(outcome),
                    style: TextStyle(
                      color: queued ? Colors.amber : Colors.lightGreen,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(verdictBody(outcome),
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Go back', style: TextStyle(color: AppTheme.textGrey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(queued ? 'Queue it' : 'Save'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Small amber "pending" badge for commitments with a queued loosening.
class PendingBadge extends StatelessWidget {
  const PendingBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_top, color: Colors.amber, size: 11),
          if (!compact) ...[
            const SizedBox(width: 3),
            const Text('change pending',
                style: TextStyle(color: Colors.amber, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}
