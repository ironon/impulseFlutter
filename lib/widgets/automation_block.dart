import 'package:flutter/material.dart';
import '../models/automation_model.dart';
import '../services/automation_service.dart';
import '../services/bluetooth_service.dart';

class AutomationBlock extends StatelessWidget {
  final Automation automation;
  final AutomationLayout layout;
  final VoidCallback onTap;

  /// True when this commitment has a queued loosening waiting (§8.9 item 5).
  final bool hasPendingChange;

  /// Honest origin label shown in Advanced mode ("Sunrise Lock" / "manual").
  final bool showOrigin;

  /// Width of the hour-label gutter this block sits to the right of.
  final double gutterWidth;

  /// Width available for the block columns (timeline width minus gutter).
  final double gridWidth;

  const AutomationBlock({
    super.key,
    required this.automation,
    required this.layout,
    required this.onTap,
    required this.gutterWidth,
    required this.gridWidth,
    this.hasPendingChange = false,
    this.showOrigin = false,
  });

  @override
  Widget build(BuildContext context) {
    final label      = _label();
    final startStr   = _fmtTime(automation.startTime);
    final endStr     = _fmtTime(automation.endTime);
    final dur        = automation.durationMinutes;

    return Positioned(
      top:    automation.startMinutes.toDouble(),
      left:   gutterWidth +
              (layout.columnIndex / layout.totalColumns) * gridWidth,
      width:  (1 / layout.totalColumns) * gridWidth,
      height: dur.toDouble(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin:  const EdgeInsets.only(right: 2, bottom: 1),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color:        automation.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
            border:       Border.all(
              color: automation.color.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasPendingChange)
                    const Icon(Icons.hourglass_top,
                        color: Colors.amber, size: 12),
                ],
              ),
              if (dur > 30) ...[
                const SizedBox(height: 2),
                Text(
                  '$startStr – $endStr',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (dur > 60) ...[
                const SizedBox(height: 2),
                Text(
                  showOrigin
                      ? '${_criteriaText()} · ${_originText()}'
                      : _criteriaText(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves the display label: anchor name or WiFi SSID.
  String _label() {
    if (automation.wifiSSID != null && automation.wifiSSID!.isNotEmpty) {
      return automation.wifiSSID!;
    }
    if (automation.anchorId != null) {
      final bt  = BluetoothService();
      final dev = bt.deviceHistory
          .where((d) => d.id == automation.anchorId)
          .firstOrNull;
      return dev?.name ?? automation.anchorId!.substring(0, 8);
    }
    return 'No target';
  }

  String _criteriaText() {
    switch (automation.criteria) {
      case Criteria.getAway:    return 'Get Away';
      case Criteria.stayNear:   return 'Stay Near';
      case Criteria.getOnWifi:  return 'Get on WiFi';
      case Criteria.getOffWifi: return 'Get off WiFi';
      case Criteria.phoneAway:  return 'Phone Away';
    }
  }

  /// Honest provenance label (§2A.3): which template made this block.
  String _originText() {
    switch (automation.origin) {
      case TemplateOrigin.manual:      return 'manual';
      case TemplateOrigin.sunriseLock: return 'Sunrise Lock';
      case TemplateOrigin.studyTime:   return 'Study Time';
      case TemplateOrigin.gymTime:     return 'Gym Time';
      case TemplateOrigin.phoneFree:   return 'Phone-Free';
    }
  }

  String _fmtTime(TimeOfDay t) {
    final h  = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m  = t.minute.toString().padLeft(2, '0');
    final pd = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $pd';
  }
}
