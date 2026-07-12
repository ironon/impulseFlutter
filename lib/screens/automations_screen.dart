import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/automation_model.dart';
import '../services/automation_service.dart';
import '../services/self_binding_policy.dart';
import '../services/watch_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/add_automation_modal.dart';
import '../widgets/automation_block.dart';
import '../widgets/policy_verdict.dart';
import 'pending_changes_screen.dart';

/// The raw-block day calendar. In Advanced mode this is the truthful view of
/// exactly what the watch enforces (§2A); every edit routes through the
/// self-binding gate (§8.9) via AppState.
class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  final AutomationService _automationService = AutomationService();
  late DateTime _selectedDate;

  /// Starts the day view around two hours before now (clamped), so the
  /// current part of the day is visible on open.
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset:
        ((DateTime.now().hour - 2) * 60.0).clamp(0.0, 18 * 60.0),
  );

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final automationsForDate =
        _automationService.getAutomationsForDate(_selectedDate);
    final layouts =
        _automationService.calculateAutomationLayouts(automationsForDate);
    final pendingIds = app.pendingEventIds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocks'),
        actions: [
          IconButton(
            tooltip: 'Pending changes',
            icon: Badge(
              isLabelVisible: pendingIds.isNotEmpty,
              backgroundColor: Colors.amber,
              label: Text('${pendingIds.length}',
                  style: const TextStyle(
                      color: AppTheme.darkGrey, fontSize: 10)),
              child: const Icon(Icons.hourglass_top),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PendingChangesScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateNavigator(),
          Expanded(
    
            child:_buildCalendarView(automationsForDate, layouts, pendingIds),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAutomation,
        backgroundColor: AppTheme.lightOrange,
        child: const Icon(Icons.add, color: AppTheme.darkGrey),
      ),
    );
  }

  Widget _buildDateNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.cardGrey,
        border: Border(
          bottom: BorderSide(color: AppTheme.backgroundGrey, width: 2),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppTheme.lightOrange),
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
            },
          ),
          Expanded(
            child: Text(
              _formatDateHeader(_selectedDate),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppTheme.lightOrange),
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.add(const Duration(days: 1));
              });
            },
          ),
        ],
      ),
    );
  }

  /// One scrollable coordinate space: hour labels, hour dividers, and the
  /// timeblocks all live inside a single fixed-height (24 × 60 px) Stack, so
  /// scrolling moves everything together. (Separate ListViews + a
  /// viewport-sized Stack made the Positioned blocks ignore scrolling.)
  Widget _buildCalendarView(
    List<Automation> automations,
    Map<String, AutomationLayout> layouts,
    Set<String> pendingIds,
  ) {
    const gutterWidth = 60.0;
    const timelineHeight = 24 * 60.0; // 1 px per minute

    return LayoutBuilder(builder: (context, constraints) {
      final gridWidth = constraints.maxWidth - gutterWidth;
      return SingleChildScrollView(
        controller: _scrollController,
        child: SizedBox(
          height: timelineHeight,
          width: constraints.maxWidth,
          child: Stack(
            children: [
              // Hour dividers + labels (one coordinate space with the blocks)
              for (int hour = 0; hour < 24; hour++) ...[
                Positioned(
                  top: hour * 60.0,
                  left: gutterWidth,
                  right: 0,
                  child: Container(height: 1, color: AppTheme.cardGrey),
                ),
                Positioned(
                  top: hour * 60.0,
                  left: 0,
                  width: gutterWidth,
                  height: 60,
                  child: Center(
                    child: Text(
                      _formatHour(hour),
                      style: const TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
              // Timeblocks, positioned on the same timeline
              ...automations.map((automation) {
                final layout = layouts[automation.id];
                if (layout == null) return const SizedBox();
                return AutomationBlock(
                  automation: automation,
                  layout: layout,
                  gutterWidth: gutterWidth,
                  gridWidth: gridWidth,
                  hasPendingChange: pendingIds.contains(automation.id),
                  showOrigin: true,
                  onTap: () => _editAutomation(automation),
                );
              }),
            ],
          ),
        ),
      );
    });
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  String _formatDateHeader(DateTime date) {
    final weekday = _getWeekdayName(date.weekday);
    final month = _getMonthName(date.month);
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (isToday) {
      return 'Today, $month ${date.day}';
    }

    return '$weekday, $month ${date.day}';
  }

  String _getWeekdayName(int weekday) => const [
        '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
      ][weekday];

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }

  void _showPushResult(ScheduleEndResult? push) {
    if (!mounted || push == null || push == ScheduleEndResult.accepted) return;
    // Surface 0x03/0x04 (and failures) honestly — never as a full apply.
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(push.userMessage)));
  }

  Future<void> _addAutomation() async {
    final app = context.read<AppState>();
    final result = await showDialog<AutomationModalResult>(
      context: context,
      builder: (context) => AddAutomationModal(
        initialDate: _selectedDate,
      ),
    );

    if (result?.saved case final a?) {
      final saved = await app.saveCommitment(updated: a);
      _showPushResult(saved.pushResult);
      setState(() {});
    }
  }

  Future<void> _editAutomation(Automation automation) async {
    final app = context.read<AppState>();
    final result = await showDialog<AutomationModalResult>(
      context: context,
      builder: (context) => AddAutomationModal(
        initialDate: _selectedDate,
        existingAutomation: automation,
      ),
    );
    if (result == null || !mounted) return;

    // ── Delete path ──
    if (result.deleteRequested) {
      final preview = app.policy.previewDelete(automation);
      final ok = await confirmWithVerdict(context,
          outcome: preview, title: 'Remove this commitment?');
      if (!ok) return;
      final res = await app.deleteCommitment(automation);
      _showPushResult(res.pushResult);
      setState(() {});
      return;
    }

    var updated = result.saved!;

    // ── Detach-to-manual (§2A.3): hand-editing a template block ──
    final changed =
        app.policy.previewEdit(automation, updated).classification !=
            ChangeClassification.noChange;
    final detached =
        automation.origin != TemplateOrigin.manual && changed;
    if (detached) {
      updated = updated.detachToManual();
    }

    // ── Preview verdict BEFORE committing ──
    if (changed) {
      final preview = app.policy.previewEdit(automation, updated);
      final ok = await confirmWithVerdict(context, outcome: preview);
      if (!ok) return;
    }

    final saved =
        await app.saveCommitment(previous: automation, updated: updated);
    _showPushResult(saved.pushResult);
    if (detached && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'This block is now custom — its template card no longer manages it.'),
      ));
    }
    setState(() {});
  }
}
