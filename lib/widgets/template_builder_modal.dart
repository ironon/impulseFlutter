import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/automation_model.dart';
import '../services/commitment_policy_service.dart';
import '../services/self_binding_policy.dart';
import '../state/app_state.dart';
import '../templates/template.dart';
import '../theme/app_theme.dart';
import '../utils/schedule_encoder.dart';
import 'policy_verdict.dart';
import 'template_form.dart';

/// Normal-mode template builder (§2A.2): friendly params in, tagged blocks
/// out. Editing regenerates the instance's blocks with stable UUIDs and runs
/// every resulting block change through the §8.9 gate.
class TemplateBuilderModal extends StatefulWidget {
  const TemplateBuilderModal({
    super.key,
    required this.template,
    this.existingBlocks = const [],
    this.initialParams,
  });

  final Template template;

  /// The blocks this template instance currently owns (empty = creating).
  final List<Automation> existingBlocks;

  /// Optional starting params (e.g. resuming a draft).
  final Map<String, dynamic>? initialParams;

  @override
  State<TemplateBuilderModal> createState() => _TemplateBuilderModalState();
}

class _TemplateBuilderModalState extends State<TemplateBuilderModal> {
  late Map<String, dynamic> _params;
  bool _saving = false;

  bool get _editing => widget.existingBlocks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _params = {
      ...widget.template.defaultParams,
      if (_editing) ...widget.template.reparse(widget.existingBlocks),
      ...?widget.initialParams,
    };
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() => _saving = true);

    final instanceId = _editing
        ? (widget.existingBlocks.first.templateInstanceId ??
            ScheduleEncoder.generateUuid())
        : ScheduleEncoder.generateUuid();

    // UUID stability (§8.9 item 3): blocks that persist reuse their UUIDs.
    final slotUuids = <String, String>{
      if (widget.existingBlocks.isNotEmpty)
        'primary': widget.existingBlocks.first.id,
    };

    final newBlocks = widget.template.expand(
      _params,
      instanceId: instanceId,
      newUuid: ScheduleEncoder.generateUuid,
      slotUuids: slotUuids,
    );

    // Preview: if any block change would queue, tell the user before saving.
    EditOutcome? worst;
    for (final nb in newBlocks) {
      final old =
          widget.existingBlocks.where((b) => b.id == nb.id).firstOrNull;
      if (old == null) continue;
      final o = app.policy.previewEdit(old, nb);
      if (o.queued) worst = o;
    }
    if (worst != null && mounted) {
      final ok = await confirmWithVerdict(context, outcome: worst);
      if (!ok) {
        setState(() => _saving = false);
        return;
      }
    }

    final outcomes =
        await app.saveTemplateBlocks(widget.existingBlocks, newBlocks);

    if (!mounted) return;
    final queued = outcomes.values.where((o) => o.queued).length;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(queued == 0
          ? '${widget.template.displayName} is set. Past-you runs the day.'
          : 'Saved — the parts that ease things take effect after a day.'),
    ));
  }

  Future<void> _delete() async {
    final app = context.read<AppState>();
    // Deleting the template = deleting all its blocks, through the gate.
    EditOutcome? worst;
    for (final b in widget.existingBlocks) {
      final o = app.policy.previewDelete(b);
      if (o.queued) worst = o;
    }
    final ok = await confirmWithVerdict(
      context,
      outcome: worst ??
          const EditOutcome(
              GateDecision.applyImmediately, ChangeClassification.loosening),
      title: 'Remove ${widget.template.displayName}?',
    );
    if (!ok) return;
    await app.saveTemplateBlocks(widget.existingBlocks, const []);
    if (mounted) Navigator.of(context).pop(true);
  }

  bool get _complete {
    for (final p in widget.template.params) {
      if (p.kind == ParamKind.anchorRole || p.kind == ParamKind.wifiSsid) {
        if (_params[p.key] == null) return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return Dialog(
      backgroundColor: AppTheme.darkGrey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.cardGrey,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(t.icon, color: AppTheme.lightOrange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.displayName,
                            style: const TextStyle(
                                color: AppTheme.textWhite,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text(t.description,
                            style: const TextStyle(
                                color: AppTheme.textGrey, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: TemplateForm(
                  params: t.params,
                  values: _params,
                  onChanged: (v) => setState(() => _params = v),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.cardGrey)),
              ),
              child: Row(
                children: [
                  if (_editing)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 18),
                      label: const Text('Remove',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppTheme.textGrey)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saving || !_complete ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.lightOrange,
                      foregroundColor: AppTheme.darkGrey,
                    ),
                    child: Text(_editing ? 'Update' : 'Set it up'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
