import 'package:flutter/material.dart';
import '../models/automation_model.dart';
import '../services/bluetooth_service.dart';
import '../theme/app_theme.dart';
import '../utils/schedule_encoder.dart';

class AddAutomationModal extends StatefulWidget {
  final DateTime initialDate;
  final Automation? existingAutomation;

  const AddAutomationModal({
    super.key,
    required this.initialDate,
    this.existingAutomation,
  });

  @override
  State<AddAutomationModal> createState() => _AddAutomationModalState();
}

class _AddAutomationModalState extends State<AddAutomationModal> {
  late DateTime          _selectedDate;
  late TimeOfDay         _startTime;
  late TimeOfDay         _endTime;
  RecurrenceType         _recurrenceType = RecurrenceType.once;
  int?                   _dayOfWeek;
  int?                   _dayOfMonth;
  Criteria               _criteria       = Criteria.stayNear;
  EnforcementProfile     _profile        = EnforcementProfile.normalSilent;
  bool                   _negate         = false;
  String?                _anchorId;
  final _wifiSsidCtrl  = TextEditingController();
  List<String>           _beepAnchors    = [];
  AnchorEnforcementProfile? _anchorProfile;
  Color                  _color          = Colors.blue;

  static const _colors = [
    Colors.blue, Colors.red, Colors.green, Colors.orange,
    Colors.purple, Colors.pink, Colors.teal, Colors.amber,
    AppTheme.lightOrange,
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;

    if (widget.existingAutomation case final a?) {
      _selectedDate   = a.referenceDate;
      _startTime      = a.startTime;
      _endTime        = a.endTime;
      _recurrenceType = a.recurrenceType;
      _dayOfWeek      = a.dayOfWeek;
      _dayOfMonth     = a.dayOfMonth;
      _criteria       = a.criteria;
      _profile        = a.profile;
      _negate         = a.negate;
      _anchorId       = a.anchorId;
      _wifiSsidCtrl.text = a.wifiSSID ?? '';
      _beepAnchors    = List.from(a.beepAnchors);
      _anchorProfile  = a.anchorProfile;
      _color          = a.color;
    } else {
      _startTime = const TimeOfDay(hour: 9,  minute: 0);
      _endTime   = const TimeOfDay(hour: 10, minute: 0);
    }
  }

  @override
  void dispose() {
    _wifiSsidCtrl.dispose();
    super.dispose();
  }

  bool get _isWifiCriteria =>
      _criteria == Criteria.getOnWifi || _criteria == Criteria.getOffWifi;

  bool get _canSave {
    if (_isWifiCriteria) return _wifiSsidCtrl.text.trim().isNotEmpty;
    return _anchorId != null;
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _save() {
    if (!_canSave) return;
    final a = Automation(
      id:             widget.existingAutomation?.id ?? ScheduleEncoder.generateUuid(),
      referenceDate:  _selectedDate,
      startTime:      _startTime,
      endTime:        _endTime,
      recurrenceType: _recurrenceType,
      dayOfWeek:      _recurrenceType == RecurrenceType.weekly  ? _dayOfWeek  : null,
      dayOfMonth:     _recurrenceType == RecurrenceType.monthly ? _dayOfMonth : null,
      criteria:       _criteria,
      profile:        _profile,
      negate:         _negate,
      anchorId:       _isWifiCriteria ? null : _anchorId,
      wifiSSID:       _isWifiCriteria ? _wifiSsidCtrl.text.trim() : null,
      beepAnchors:    _beepAnchors,
      anchorProfile:  _beepAnchors.isEmpty ? null : _anchorProfile,
      color:          _color,
    );
    Navigator.of(context).pop(a);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkGrey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
          maxWidth:  500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTimePickers(),
                    const SizedBox(height: 20),
                    _buildRecurrence(),
                    const SizedBox(height: 20),
                    _buildCriteria(),
                    const SizedBox(height: 20),
                    _buildTarget(),
                    const SizedBox(height: 20),
                    _buildProfile(),
                    const SizedBox(height: 20),
                    _buildBeepAnchors(),
                    const SizedBox(height: 20),
                    _buildColorPicker(),
                    const SizedBox(height: 20),
                    _buildNegate(),
                  ],
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: const BoxDecoration(
          color: AppTheme.cardGrey,
          borderRadius: BorderRadius.only(
            topLeft:  Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppTheme.lightOrange),
              onPressed: () => setState(() =>
                  _selectedDate = _selectedDate.subtract(const Duration(days: 1))),
            ),
            Expanded(
              child: Text(
                _fmtDate(_selectedDate),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppTheme.lightOrange),
              onPressed: () => setState(() =>
                  _selectedDate = _selectedDate.add(const Duration(days: 1))),
            ),
          ],
        ),
      );

  // ── Time pickers ──────────────────────────────────────────────────────────

  Widget _buildTimePickers() => Row(
        children: [
          Expanded(child: _timePicker('Start Time', _startTime, true)),
          const SizedBox(width: 16),
          Expanded(child: _timePicker('End Time',   _endTime,   false)),
        ],
      );

  Widget _timePicker(String label, TimeOfDay time, bool isStart) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickTime(isStart),
            child: _inputBox(Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmtTime(time),
                    style: const TextStyle(color: AppTheme.textWhite, fontSize: 16)),
                const Icon(Icons.access_time,
                    color: AppTheme.lightOrange, size: 20),
              ],
            )),
          ),
        ],
      );

  // ── Recurrence ────────────────────────────────────────────────────────────

  Widget _buildRecurrence() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Recurring'),
          const SizedBox(height: 12),
          _radioOption('Once',                  RecurrenceType.once,    null, null),
          const SizedBox(height: 8),
          _radioOption('Every day',             RecurrenceType.daily,   null, null),
          const SizedBox(height: 8),
          _radioOption(
            'Every ${_weekdayName(_selectedDate.weekday)}',
            RecurrenceType.weekly,
            _selectedDate.weekday, null,
          ),
          const SizedBox(height: 8),
          _radioOption(
            'Every ${_ordinal(_selectedDate.day)} of the month',
            RecurrenceType.monthly,
            null, _selectedDate.day,
          ),
        ],
      );

  Widget _radioOption(String label, RecurrenceType type,
      int? dow, int? dom) {
    final selected = _recurrenceType == type;
    return InkWell(
      onTap: () => setState(() {
        _recurrenceType = type;
        _dayOfWeek  = dow;
        _dayOfMonth = dom;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.lightOrange.withValues(alpha: 0.2)
              : AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.lightOrange : AppTheme.cardGrey,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? AppTheme.lightOrange : AppTheme.textGrey,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                  color: selected ? AppTheme.lightOrange : AppTheme.textWhite,
                  fontSize: 14,
                )),
          ],
        ),
      ),
    );
  }

  // ── Criteria ──────────────────────────────────────────────────────────────

  Widget _buildCriteria() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Criteria'),
          const SizedBox(height: 12),
          _dropdown<Criteria>(
            value: _criteria,
            items: const [
              DropdownMenuItem(value: Criteria.stayNear,   child: Text('Stay Near anchor')),
              DropdownMenuItem(value: Criteria.getAway,    child: Text('Get Away from anchor')),
              DropdownMenuItem(value: Criteria.getOnWifi,  child: Text('Get On WiFi network')),
              DropdownMenuItem(value: Criteria.getOffWifi, child: Text('Get Off WiFi network')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _criteria = v);
            },
          ),
        ],
      );

  // ── Target (anchor picker or WiFi SSID) ───────────────────────────────────

  Widget _buildTarget() {
    if (_isWifiCriteria) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('WiFi Network (SSID)'),
          const SizedBox(height: 12),
          TextField(
            controller: _wifiSsidCtrl,
            style: const TextStyle(color: AppTheme.textWhite),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. MyHomeNetwork',
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
          ),
        ],
      );
    }

    // Anchor picker
    final anchors = BluetoothService().anchors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Target Anchor'),
        const SizedBox(height: 12),
        if (anchors.isEmpty)
          const Text(
            'No anchors discovered yet. Go to Devices tab and scan.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
          )
        else
          _dropdown<String>(
            value: anchors.any((a) => a.id == _anchorId) ? _anchorId : null,
            items: anchors.map((a) =>
                DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
            hint: 'Select anchor',
            onChanged: (v) => setState(() => _anchorId = v),
          ),
      ],
    );
  }

  // ── Enforcement profile ───────────────────────────────────────────────────

  Widget _buildProfile() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Enforcement Profile'),
          const SizedBox(height: 12),
          _dropdown<EnforcementProfile>(
            value: _profile,
            items: EnforcementProfile.values
                .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: (v) { if (v != null) setState(() => _profile = v); },
          ),
        ],
      );

  // ── Beep anchors ──────────────────────────────────────────────────────────

  Widget _buildBeepAnchors() {
    final anchors = BluetoothService().anchors;
    if (anchors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Anchors to Beep on Watch Removal'),
        const SizedBox(height: 4),
        const Text(
          'These anchors will beep if the watch is taken off during this event.',
          style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...anchors.map((a) {
          final selected = _beepAnchors.contains(a.id);
          return CheckboxListTile(
            title: Text(a.name,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: 14)),
            value: selected,
            activeColor: AppTheme.lightOrange,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _beepAnchors.add(a.id);
                  _anchorProfile ??= AnchorEnforcementProfile.medium;
                } else {
                  _beepAnchors.remove(a.id);
                }
              });
            },
          );
        }),
        if (_beepAnchors.isNotEmpty) ...[
          const SizedBox(height: 8),
          _label('Beep Pattern'),
          const SizedBox(height: 8),
          _dropdown<AnchorEnforcementProfile>(
            value: _anchorProfile ?? AnchorEnforcementProfile.medium,
            items: AnchorEnforcementProfile.values
                .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: (v) { if (v != null) setState(() => _anchorProfile = v); },
          ),
        ],
      ],
    );
  }

  // ── Color picker ──────────────────────────────────────────────────────────

  Widget _buildColorPicker() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Color'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _colors.map((c) {
              final sel = _color == c;
              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? AppTheme.textWhite : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: sel
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      );

  // ── Negate toggle ─────────────────────────────────────────────────────────

  Widget _buildNegate() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cardGrey),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cancel recurring event',
                    style: TextStyle(color: AppTheme.textWhite, fontSize: 14)),
                Text('Removes a recurring event on this specific day',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
              ],
            ),
            Switch(
              value: _negate,
              onChanged: (v) => setState(() => _negate = v),
              activeTrackColor: AppTheme.lightOrange,
            ),
          ],
        ),
      );

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActions() => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.cardGrey)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lightOrange,
                foregroundColor: AppTheme.darkGrey,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(
                widget.existingAutomation != null ? 'Update' : 'Save',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked  = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   AppTheme.lightOrange,
            onPrimary: AppTheme.darkGrey,
            surface:   AppTheme.cardGrey,
            onSurface: AppTheme.textWhite,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) { _startTime = picked; }
        else         { _endTime   = picked; }
      });
    }
  }

  Widget _inputBox(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cardGrey),
        ),
        child: child,
      );

  Widget _dropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cardGrey),
        ),
        child: DropdownButton<T>(
          value: value,
          hint: hint != null
              ? Text(hint, style: const TextStyle(color: AppTheme.textGrey))
              : null,
          isExpanded: true,
          dropdownColor: AppTheme.cardGrey,
          underline: const SizedBox(),
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 15),
          items: items,
          onChanged: onChanged,
        ),
      );

  Widget _title(String t) => Text(t,
      style: const TextStyle(
          color: AppTheme.textWhite, fontSize: 16, fontWeight: FontWeight.bold));

  Widget _label(String t) => Text(t,
      style: const TextStyle(color: AppTheme.textGrey, fontSize: 14));

  String _fmtTime(TimeOfDay t) {
    final h  = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m  = t.minute.toString().padLeft(2, '0');
    final pd = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $pd';
  }

  String _fmtDate(DateTime d) {
    final wd = _weekdayName(d.weekday);
    final mo = _monthName(d.month);
    return '$wd, $mo ${d.day}, ${d.year}';
  }

  String _weekdayName(int wd) => const [
        '', 'Monday', 'Tuesday', 'Wednesday',
        'Thursday', 'Friday', 'Saturday', 'Sunday'
      ][wd];

  String _monthName(int m) => const [
        '', 'January', 'February', 'March', 'April',
        'May', 'June', 'July', 'August', 'September',
        'October', 'November', 'December'
      ][m];

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }
}
