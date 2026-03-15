import 'package:flutter/material.dart';
import '../models/automation_model.dart';
import '../services/automation_service.dart';
import '../theme/app_theme.dart';
import '../widgets/add_automation_modal.dart';
import '../widgets/automation_block.dart';

class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  final AutomationService _automationService = AutomationService();
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _automationService.initialize();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final automationsForDate = _automationService.getAutomationsForDate(_selectedDate);
    final layouts = _automationService.calculateAutomationLayouts(automationsForDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Automations'),
      ),
      body: Column(
        children: [
          _buildDateNavigator(),
          Expanded(
            child: _buildCalendarView(automationsForDate, layouts),
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

  Widget _buildCalendarView(
    List<Automation> automations,
    Map<String, AutomationLayout> layouts,
  ) {
    return Row(
      children: [
        // Time labels column
        SizedBox(
          width: 60,
          child: ListView.builder(
            itemCount: 24,
            itemBuilder: (context, index) {
              return SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    _formatHour(index),
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Calendar grid
        Expanded(
          child: Stack(
            children: [
              // Hour dividers
              ListView.builder(
                itemCount: 24,
                itemBuilder: (context, index) {
                  return Container(
                    height: 60,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppTheme.cardGrey, width: 1),
                      ),
                    ),
                  );
                },
              ),
              // Automation blocks
              ...automations.map((automation) {
                final layout = layouts[automation.id];
                if (layout == null) return const SizedBox();
                return AutomationBlock(
                  automation: automation,
                  layout: layout,
                  onTap: () => _editAutomation(automation),
                );
              }),
            ],
          ),
        ),
      ],
    );
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

  String _getWeekdayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Future<void> _addAutomation() async {
    final result = await showDialog<Automation>(
      context: context,
      builder: (context) => AddAutomationModal(
        initialDate: _selectedDate,
      ),
    );

    if (result != null) {
      await _automationService.addAutomation(result);
      setState(() {});
    }
  }

  Future<void> _editAutomation(Automation automation) async {
    final result = await showDialog<Automation?>(
      context: context,
      builder: (context) => AddAutomationModal(
        initialDate: _selectedDate,
        existingAutomation: automation,
      ),
    );

    if (result != null) {
      await _automationService.updateAutomation(result);
      setState(() {});
    }
  }
}
