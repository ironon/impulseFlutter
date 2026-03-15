import 'package:flutter/material.dart';
import 'package:impulse_app/services/bluetooth_service.dart';
import '../models/automation_model.dart';
import '../models/bluetooth_device_model.dart';
import '../theme/app_theme.dart';

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
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  RecurrenceType _recurrenceType = RecurrenceType.once;
  int? _dayOfWeek;
  String? _selectedDeviceId;
  Criteria _criteria = Criteria.stayNear;
  Color _selectedColor = Colors.blue;
  bool _strictMode = false;
  Importance _importance = Importance.medium;

  final List<Color> _availableColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.amber,
    AppTheme.lightOrange,
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;

    if (widget.existingAutomation != null) {
      final automation = widget.existingAutomation!;
      _selectedDate = automation.date;
      _startTime = automation.startTime;
      _endTime = automation.endTime;
      _recurrenceType = automation.recurrenceType;
      _dayOfWeek = automation.dayOfWeek;
      _selectedDeviceId = automation.deviceId;
      _criteria = automation.criteria;
      _selectedColor = automation.color;
      _strictMode = automation.strictMode;
      _importance = automation.importance;
    } else {
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkGrey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: 500,
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
                    _buildRecurringSection(),
                    const SizedBox(height: 20),
                    _buildDeviceSelector(),
                    const SizedBox(height: 20),
                    _buildCriteriaSelector(),
                    const SizedBox(height: 20),
                    _buildColorPicker(),
                    const SizedBox(height: 24),
                    _buildSettingsSection(),
                  ],
                ),
              ),
            ),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardGrey,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
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

  Widget _buildTimePickers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Start Time',
                    style: TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _selectTime(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundGrey,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardGrey),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTimeOfDay(_startTime),
                            style: const TextStyle(
                              color: AppTheme.textWhite,
                              fontSize: 16,
                            ),
                          ),
                          const Icon(
                            Icons.access_time,
                            color: AppTheme.lightOrange,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'End Time',
                    style: TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _selectTime(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundGrey,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardGrey),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTimeOfDay(_endTime),
                            style: const TextStyle(
                              color: AppTheme.textWhite,
                              fontSize: 16,
                            ),
                          ),
                          const Icon(
                            Icons.access_time,
                            color: AppTheme.lightOrange,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecurringSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recurring',
          style: TextStyle(
            color: AppTheme.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildRecurringOption(
          'Once',
          RecurrenceType.once,
          null,
        ),
        const SizedBox(height: 8),
        _buildRecurringOption(
          'Every day at this time',
          RecurrenceType.daily,
          null,
        ),
        const SizedBox(height: 8),
        _buildRecurringOption(
          'Every ${_getWeekdayName(_selectedDate.weekday)} at this time',
          RecurrenceType.weekly,
          _selectedDate.weekday,
        ),
      ],
    );
  }

  Widget _buildRecurringOption(
    String label,
    RecurrenceType type,
    int? dayOfWeek,
  ) {
    final isSelected = _recurrenceType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _recurrenceType = type;
          _dayOfWeek = dayOfWeek;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.lightOrange.withValues(alpha: 0.2) : AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.lightOrange : AppTheme.cardGrey,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.lightOrange : AppTheme.textGrey,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.lightOrange : AppTheme.textWhite,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSelector() {
    final bluetoothService = BluetoothService();
    final devices = bluetoothService.deviceHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Device',
          style: TextStyle(
            color: AppTheme.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.backgroundGrey,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardGrey),
          ),
          child: DropdownButton<String>(
            value: _selectedDeviceId,
            hint: const Text(
              'Select a device',
              style: TextStyle(color: AppTheme.textGrey),
            ),
            isExpanded: true,
            dropdownColor: AppTheme.cardGrey,
            underline: const SizedBox(),
            style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 16,
            ),
            items: devices.map((BluetoothDeviceModel device) {
              return DropdownMenuItem<String>(
                value: device.id,
                child: Text(device.name),
              );
            }).toList(),
            onChanged: (String? value) {
              setState(() {
                _selectedDeviceId = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCriteriaSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Criteria',
          style: TextStyle(
            color: AppTheme.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.backgroundGrey,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardGrey),
          ),
          child: DropdownButton<Criteria>(
            value: _criteria,
            isExpanded: true,
            dropdownColor: AppTheme.cardGrey,
            underline: const SizedBox(),
            style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 16,
            ),
            items: const [
              DropdownMenuItem(
                value: Criteria.getAway,
                child: Text('Get Away'),
              ),
              DropdownMenuItem(
                value: Criteria.stayNear,
                child: Text('Stay Near'),
              ),
            ],
            onChanged: (Criteria? value) {
              if (value != null) {
                setState(() {
                  _criteria = value;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Color',
          style: TextStyle(
            color: AppTheme.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _availableColors.map((color) {
            final isSelected = _selectedColor == color;
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppTheme.textWhite : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            color: AppTheme.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundGrey,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardGrey),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Strict Mode',
                    style: TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 14,
                    ),
                  ),
                  Switch(
                    value: _strictMode,
                    onChanged: (value) {
                      setState(() {
                        _strictMode = value;
                      });
                    },
                    activeTrackColor: AppTheme.lightOrange,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Importance',
                    style: TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 14,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardGrey,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<Importance>(
                      value: _importance,
                      dropdownColor: AppTheme.cardGrey,
                      underline: const SizedBox(),
                      style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: 14,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: Importance.low,
                          child: Text('Low'),
                        ),
                        DropdownMenuItem(
                          value: Importance.medium,
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(
                          value: Importance.high,
                          child: Text('High'),
                        ),
                      ],
                      onChanged: (Importance? value) {
                        if (value != null) {
                          setState(() {
                            _importance = value;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.cardGrey),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textGrey),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _canSave() ? _saveAutomation : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.lightOrange,
              foregroundColor: AppTheme.darkGrey,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              widget.existingAutomation != null ? 'Update' : 'Save',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  bool _canSave() {
    return _selectedDeviceId != null;
  }

  void _saveAutomation() {
    if (!_canSave()) return;

    final automation = Automation(
      id: widget.existingAutomation?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      date: _selectedDate,
      startTime: _startTime,
      endTime: _endTime,
      recurrenceType: _recurrenceType,
      dayOfWeek: _dayOfWeek,
      deviceId: _selectedDeviceId!,
      criteria: _criteria,
      color: _selectedColor,
      strictMode: _strictMode,
      importance: _importance,
    );

    Navigator.of(context).pop(automation);
  }

  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final initialTime = isStartTime ? _startTime : _endTime;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.lightOrange,
              onPrimary: AppTheme.darkGrey,
              surface: AppTheme.cardGrey,
              onSurface: AppTheme.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDateHeader(DateTime date) {
    final weekday = _getWeekdayName(date.weekday);
    final month = _getMonthName(date.month);
    return '$weekday, $month ${date.day}, ${date.year}';
  }

  String _getWeekdayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }
}
