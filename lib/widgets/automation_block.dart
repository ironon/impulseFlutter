import 'package:flutter/material.dart';
import 'package:impulse_app/services/bluetooth_service.dart';
import '../models/automation_model.dart';
import '../services/automation_service.dart';

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
    final deviceName = _getDeviceName();
    final startTimeStr = _formatTime(automation.startTime);
    final endTimeStr = _formatTime(automation.endTime);

    return Positioned(
      top: automation.startMinutes.toDouble(),
      left: (layout.columnIndex / layout.totalColumns) *
            MediaQuery.of(context).size.width * 0.85,
      width: (1 / layout.totalColumns) *
             MediaQuery.of(context).size.width * 0.85,
      height: automation.durationMinutes.toDouble(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 2, bottom: 1),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: automation.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: automation.color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deviceName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (automation.durationMinutes > 30) ...[
                const SizedBox(height: 2),
                Text(
                  '$startTimeStr - $endTimeStr',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (automation.durationMinutes > 60) ...[
                const SizedBox(height: 2),
                Text(
                  _getCriteriaText(),
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

  String _getDeviceName() {
    final bluetoothService = BluetoothService();
    final device = bluetoothService.deviceHistory
        .where((d) => d.id == automation.deviceId)
        .firstOrNull;
    return device?.name ?? 'Unknown Device';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _getCriteriaText() {
    switch (automation.criteria) {
      case Criteria.getAway:
        return 'Get Away';
      case Criteria.stayNear:
        return 'Stay Near';
    }
  }
}
