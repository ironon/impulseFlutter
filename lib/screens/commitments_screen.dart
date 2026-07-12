import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/automation_model.dart';
import '../state/app_state.dart';
import '../templates/template.dart';
import '../theme/app_theme.dart';
import '../widgets/policy_verdict.dart';
import '../widgets/template_builder_modal.dart';
import 'pending_changes_screen.dart';

/// Normal-mode commitments view (§2A): friendly template cards grouped by
/// templateInstanceId, generic "Custom" cards for manual blocks (never
/// hidden), drafts, and a registry-generated template gallery to add more.
class CommitmentsScreen extends StatelessWidget {
  const CommitmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pendingIds = app.pendingEventIds;

    // Group template-produced blocks by instance; collect manual blocks.
    final instances = <String, List<Automation>>{};
    final manual = <Automation>[];
    for (final a in app.schedule) {
      final iid = a.templateInstanceId;
      if (a.origin == TemplateOrigin.manual || iid == null) {
        manual.add(a);
      } else {
        instances.putIfAbsent(iid, () => []).add(a);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commitments'),
        actions: [
          IconButton(
            tooltip: 'Pending changes',
            icon: Badge(
              isLabelVisible: pendingIds.isNotEmpty,
              backgroundColor: Colors.amber,
              label: Text('${pendingIds.length}',
                  style:
                      const TextStyle(color: AppTheme.darkGrey, fontSize: 10)),
              child: const Icon(Icons.hourglass_top),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PendingChangesScreen())),
          ),
        ],
      ),
      body: (instances.isEmpty && manual.isEmpty && app.drafts.isEmpty)
          ? _emptyState(context)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final draft in app.drafts) _DraftCard(draft: draft),
                for (final entry in instances.entries)
                  _TemplateCard(
                    instanceId: entry.key,
                    blocks: entry.value,
                    pendingIds: pendingIds,
                  ),
                for (final block in manual)
                  _CustomCard(block: block, pendingIds: pendingIds),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTemplateGallery(context),
        backgroundColor: AppTheme.lightOrange,
        icon: const Icon(Icons.add, color: AppTheme.darkGrey),
        label: const Text('Add a commitment',
            style: TextStyle(
                color: AppTheme.darkGrey, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.self_improvement,
                  color: AppTheme.textGrey, size: 48),
              const SizedBox(height: 16),
              const Text('Nothing on the books yet',
                  style: TextStyle(color: AppTheme.textWhite, fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                'Pick something you\'re tired of fighting yourself about, set '
                'it up once, and let the hardware carry it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

/// The registry-generated template gallery (§2A.2). Also reused as the
/// "add another goal" entry point.
Future<void> showTemplateGallery(BuildContext context) async {
  final app = context.read<AppState>();
  final template = await showModalBottomSheet<Template>(
    context: context,
    backgroundColor: AppTheme.darkGrey,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What do you want to stop fighting yourself about?',
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            for (final t in app.registry.all)
              ListTile(
                leading: Icon(t.icon, color: AppTheme.lightOrange),
                title: Text(t.displayName,
                    style: const TextStyle(color: AppTheme.textWhite)),
                subtitle: Text(t.description,
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: 12)),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
          ],
        ),
      ),
    ),
  );
  if (template == null || !context.mounted) return;
  await showDialog<bool>(
    context: context,
    builder: (_) => TemplateBuilderModal(template: template),
  );
}

// ── Template instance card ───────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.instanceId,
    required this.blocks,
    required this.pendingIds,
  });

  final String instanceId;
  final List<Automation> blocks;
  final Set<String> pendingIds;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final template = app.registry.all
        .where((t) => t.origin == blocks.first.origin)
        .firstOrNull;
    final hasPending = blocks.any((b) => pendingIds.contains(b.id));
    final b = blocks.first;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(template?.icon ?? Icons.event,
            color: AppTheme.lightOrange, size: 32),
        title: Row(
          children: [
            Flexible(
              child: Text(template?.displayName ?? 'Commitment',
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            if (hasPending) ...[
              const SizedBox(width: 8),
              const PendingBadge(),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_fmtTime(b.startTime)}–${_fmtTime(b.endTime)} · ${_recurrence(b)}'
            '${blocks.length > 1 ? ' · ${blocks.length} parts' : ''}',
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textGrey),
        onTap: template == null
            ? null
            : () => showDialog<bool>(
                  context: context,
                  builder: (_) => TemplateBuilderModal(
                    template: template,
                    existingBlocks: blocks,
                  ),
                ),
      ),
    );
  }
}

// ── Custom (manual) block card — read-only in Normal mode (§2A.3) ────────────

class _CustomCard extends StatelessWidget {
  const _CustomCard({required this.block, required this.pendingIds});

  final Automation block;
  final Set<String> pendingIds;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(Icons.build_circle_outlined,
            color: block.color, size: 32),
        title: Row(
          children: [
            const Flexible(
              child: Text('Custom',
                  style: TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            if (pendingIds.contains(block.id)) ...[
              const SizedBox(width: 8),
              const PendingBadge(),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${block.criteria.label} · ${_fmtTime(block.startTime)}–'
            '${_fmtTime(block.endTime)} · ${_recurrence(block)}\n'
            'Built block-by-block — edit it in Advanced mode.',
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}

// ── Draft card (§8.1 deferral) ───────────────────────────────────────────────

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.draft});

  final TemplateDraft draft;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final template = app.registry.byId(draft.templateId);
    if (template == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.textGrey, width: 1),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(template.icon, color: AppTheme.textGrey, size: 32),
        title: Text('${template.displayName} — draft',
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            draft.note.isEmpty
                ? 'Saved for later — not running yet.'
                : '${draft.note} · Not running yet.',
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
          ),
        ),
        trailing: IconButton(
          tooltip: 'Discard draft',
          icon: const Icon(Icons.close, color: AppTheme.textGrey, size: 20),
          onPressed: () => app.removeDraft(draft.id),
        ),
        onTap: () async {
          final done = await showDialog<bool>(
            context: context,
            builder: (_) => TemplateBuilderModal(
              template: template,
              initialParams: draft.params,
            ),
          );
          if (done == true) await app.removeDraft(draft.id);
        },
      ),
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

String _fmtTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

String _recurrence(Automation a) {
  switch (a.recurrenceType) {
    case RecurrenceType.once:
      return 'once';
    case RecurrenceType.daily:
      return 'every day';
    case RecurrenceType.weekly:
      const wd = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return 'every ${wd[a.dayOfWeek ?? 1]}';
    case RecurrenceType.monthly:
      return 'monthly (day ${a.dayOfMonth})';
  }
}
