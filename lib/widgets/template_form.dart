import 'package:flutter/material.dart';

import '../models/automation_model.dart';
import '../services/bluetooth_service.dart';
import '../templates/template.dart';
import '../theme/app_theme.dart';

/// A form generated from a template's params schema (§2A.2). Used by the
/// Normal-mode template builder and the onboarding quick-form — the UI is
/// derived from the registry, never hardcoded per template.
class TemplateForm extends StatefulWidget {
  const TemplateForm({
    super.key,
    required this.params,
    required this.values,
    required this.onChanged,
  });

  /// The schema subset to render (full params or the quick-form subset).
  final List<TemplateParam> params;

  /// Current values (mutated copies are reported via [onChanged]).
  final Map<String, dynamic> values;

  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends State<TemplateForm> {
  late Map<String, dynamic> _values;
  final Map<String, TextEditingController> _textCtrls = {};

  @override
  void initState() {
    super.initState();
    _values = Map.of(widget.values);
  }

  @override
  void dispose() {
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, dynamic value) {
    setState(() => _values[key] = value);
    widget.onChanged(Map.of(_values));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in widget.params) ...[
          Text(p.label,
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _field(p),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _field(TemplateParam p) {
    switch (p.kind) {
      case ParamKind.time:
        return _timeField(p);
      case ParamKind.durationSeconds:
        return _durationField(p);
      case ParamKind.firmness:
        return _firmnessField(p);
      case ParamKind.anchorRole:
        return _anchorField(p);
      case ParamKind.wifiSsid:
        return _textField(p, hint: 'e.g. GymGuestWiFi');
    }
  }

  // ── Time ──
  Widget _timeField(TemplateParam p) {
    final v = _values[p.key];
    final t = v is Map
        ? TimeOfDay(hour: v['hour'] as int, minute: v['minute'] as int)
        : const TimeOfDay(hour: 9, minute: 0);
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: t);
        if (picked != null) {
          _set(p.key, {'hour': picked.hour, 'minute': picked.minute});
        }
      },
      child: _box(Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_fmtTime(t),
              style: const TextStyle(color: AppTheme.textWhite, fontSize: 16)),
          const Icon(Icons.access_time, color: AppTheme.lightOrange, size: 20),
        ],
      )),
    );
  }

  // ── Duration (seconds, 0–1800) ──
  Widget _durationField(TemplateParam p) {
    final v = (_values[p.key] as int?) ?? (p.defaultValue as int? ?? 0);
    final minutes = v ~/ 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Slider(
          value: v.toDouble().clamp(0, 1800),
          min: 0,
          max: 1800,
          divisions: 30,
          activeColor: AppTheme.lightOrange,
          label: '$minutes min',
          onChanged: (nv) => _set(p.key, (nv ~/ 60) * 60),
        ),
        Text(
          v == 0 ? 'No grace — checks start right away' : '$minutes minutes of quiet after you put the watch on',
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
        ),
      ],
    );
  }

  // ── Firmness ──
  Widget _firmnessField(TemplateParam p) {
    final current = EnforcementProfile.values.firstWhere(
      (e) => e.name == (_values[p.key] ?? p.defaultValue ?? 'normalBuzz'),
      orElse: () => EnforcementProfile.normalBuzz,
    );
    return _box(DropdownButton<EnforcementProfile>(
      value: current,
      isExpanded: true,
      dropdownColor: AppTheme.cardGrey,
      underline: const SizedBox(),
      style: const TextStyle(color: AppTheme.textWhite, fontSize: 15),
      items: EnforcementProfile.values
          .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
          .toList(),
      onChanged: (v) {
        if (v != null) _set(p.key, v.name);
      },
    ));
  }

  // ── Anchor picker (role-aware) ──
  Widget _anchorField(TemplateParam p) {
    final anchors = BluetoothService().anchors;
    if (anchors.isEmpty) {
      return const Text(
        'No anchors yet — pair one from Devices first.',
        style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
      );
    }
    // Prefer anchors already tagged with the required role, but allow any.
    final sorted = List.of(anchors)
      ..sort((a, b) {
        final am = a.role == p.anchorRole ? 0 : 1;
        final bm = b.role == p.anchorRole ? 0 : 1;
        return am.compareTo(bm);
      });
    final currentId = _values[p.key] as String?;
    return _box(DropdownButton<String>(
      value: sorted.any((a) => a.id == currentId) ? currentId : null,
      hint: Text(
          p.anchorRole == null
              ? 'Pick an anchor'
              : 'Pick your ${p.anchorRole} anchor',
          style: const TextStyle(color: AppTheme.textGrey)),
      isExpanded: true,
      dropdownColor: AppTheme.cardGrey,
      underline: const SizedBox(),
      style: const TextStyle(color: AppTheme.textWhite, fontSize: 15),
      items: sorted
          .map((a) => DropdownMenuItem(
                value: a.id,
                child: Text(a.role == null ? a.name : '${a.name} (${a.role})'),
              ))
          .toList(),
      onChanged: (v) => _set(p.key, v),
    ));
  }

  // ── Text ──
  Widget _textField(TemplateParam p, {String? hint}) {
    final ctrl = _textCtrls.putIfAbsent(
        p.key, () => TextEditingController(text: _values[p.key] as String? ?? ''));
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AppTheme.textWhite),
      onChanged: (v) => _set(p.key, v.trim().isEmpty ? null : v.trim()),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textGrey),
        filled: true,
        fillColor: AppTheme.backgroundGrey,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.cardGrey)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.cardGrey)),
      ),
    );
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cardGrey),
        ),
        child: child,
      );

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }
}
