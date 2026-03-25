import 'package:flutter/material.dart';
import '../models/automation_model.dart';
import '../services/automation_service.dart';
import '../services/bluetooth_service.dart';

class AutomationBlock extends StatelessWidget {
  final Automation automation;
  final AutomationLayout layout;
  final VoidCallback onTap;

  const AutomationBlock({
    super.key,
    required this.automation,
    required this.layout,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label      = _label();
    final startStr   = _fmtTime(automation.startTime);
    final endStr     = _fmtTime(automation.endTime);
    final dur        = automation.durationMinutes;

    return Positioned(
      top:    automation.startMinutes.toDouble(),
      left:   (layout.columnIndex / layout.totalColumns) *
              MediaQuery.of(context).size.width * 0.85,
      width:  (1 / layout.totalColumns) *
              MediaQuery.of(context).size.width * 0.85,
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
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                  _criteriaText(),
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
    }
  }

  String _fmtTime(TimeOfDay t) {
    final h  = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m  = t.minute.toString().padLeft(2, '0');
    final pd = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $pd';
  }
}
