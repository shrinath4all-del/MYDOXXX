import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../utils/ist_clock.dart';

class DoctorScheduleScreen extends StatefulWidget {
  final UserModel doctor;

  const DoctorScheduleScreen({
    super.key,
    required this.doctor,
  });

  @override
  State<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends State<DoctorScheduleScreen> {
  DateTime _selectedDate = IstClock.now();
  bool _isAvailableOnDate = true;
  static const List<String> _initialSlots = [
    '09:00 AM - 10:00 AM',
    '10:00 AM - 11:00 AM',
    '11:00 AM - 12:00 PM',
    '02:00 PM - 03:00 PM',
    '04:00 PM - 05:00 PM',
    '06:00 PM - 07:00 PM',
  ];
  List<String> _selectedTimeSlots = List<String>.from(_initialSlots);

  bool _isLoading = false;

  // One-hour slots a doctor can switch on or off (8 AM to 11 PM)
  final List<String> _allDefaultSlots = [
    '08:00 AM - 09:00 AM',
    '09:00 AM - 10:00 AM',
    '10:00 AM - 11:00 AM',
    '11:00 AM - 12:00 PM',
    '12:00 PM - 01:00 PM',
    '01:00 PM - 02:00 PM',
    '02:00 PM - 03:00 PM',
    '03:00 PM - 04:00 PM',
    '04:00 PM - 05:00 PM',
    '05:00 PM - 06:00 PM',
    '06:00 PM - 07:00 PM',
    '07:00 PM - 08:00 PM',
    '08:00 PM - 09:00 PM',
    '09:00 PM - 10:00 PM',
    '10:00 PM - 11:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _loadScheduleForSelectedDate();
  }

  String _formatDateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadScheduleForSelectedDate() async {
    setState(() => _isLoading = true);
    final dateKey = _formatDateKey(_selectedDate);

    final data = await FirestoreService.getDoctorDateSchedule(
      doctorUid: widget.doctor.uid,
      dateKey: dateKey,
    );

    if (mounted) {
      if (data != null) {
        setState(() {
          _isAvailableOnDate = data['isAvailable'] ?? true;
          _selectedTimeSlots = List<String>.from(data['timeSlots'] ?? []);
          _isLoading = false;
        });
      } else {
        // Default initialized schedule
        setState(() {
          _isAvailableOnDate = true;
          _selectedTimeSlots = List<String>.from(_initialSlots);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSchedule() async {
    // Slots must not overlap (e.g. 07:00-08:00 and 07:15-07:30)
    if (_isAvailableOnDate) {
      for (final slot in _selectedTimeSlots) {
        final conflict = _conflictWith(slot);
        if (conflict != null) {
          _warnOverlap(slot, conflict);
          return;
        }
      }
    }
    setState(() => _isLoading = true);
    final dateKey = _formatDateKey(_selectedDate);

    try {
      await FirestoreService.saveDoctorDateSchedule(
        doctorUid: widget.doctor.uid,
        dateKey: dateKey,
        isAvailable: _isAvailableOnDate,
        timeSlots: _visibleSlots.where(_selectedTimeSlots.contains).toList(), // in time order
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAvailableOnDate
                ? 'Schedule saved for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} (${_selectedTimeSlots.length} slots)'
                : 'Marked as BUSY for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
          ),
          backgroundColor: AppTheme.primaryTeal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.of(e, action: 'save your schedule')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Start / end minutes of a slot ("07:00 PM - 08:00 PM"). A single time
  /// (older schedules) counts as one hour.
  static (int, int)? _range(String slot) {
    final parts = slot.split('-');
    final a = FirestoreService.timeSlotMinutes(parts.first.trim());
    if (a >= 24 * 60) return null;
    if (parts.length > 1) {
      final b = FirestoreService.timeSlotMinutes(parts[1].trim());
      if (b < 24 * 60 && b > a) return (a, b);
    }
    return (a, a + 60);
  }

  static bool _overlap(String x, String y) {
    final a = _range(x);
    final b = _range(y);
    if (a == null || b == null) return false;
    return a.$1 < b.$2 && b.$1 < a.$2;
  }

  /// A switched-on slot (other than [slot] itself) that overlaps [slot].
  String? _conflictWith(String slot) {
    for (final other in _selectedTimeSlots) {
      if (other != slot && _overlap(slot, other)) return other;
    }
    return null;
  }

  void _warnOverlap(String slot, String other) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$slot overlaps with $other. Slots cannot overlap: '
            'switch that slot off first or choose a different time.'),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  static String _fmt(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} '
        '${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  /// Doctor adds his own slot, e.g. 02:00 PM - 03:00 PM.
  Future<void> _addCustomSlot() async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 14, minute: 0),
      helpText: 'SLOT STARTS AT',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute),
      helpText: 'SLOT ENDS AT',
    );
    if (end == null || !mounted) return;

    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The end time must be after the start time.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final slot = '${_fmt(start)} - ${_fmt(end)}';
    final conflict = _conflictWith(slot);
    if (conflict != null) {
      _warnOverlap(slot, conflict);
      return;
    }
    setState(() {
      if (!_selectedTimeSlots.contains(slot)) _selectedTimeSlots.add(slot);
    });
  }

  /// Default slots plus any custom slots added for this date, in time order,
  /// so custom slots show up (and can be toggled off) like the defaults.
  List<String> get _visibleSlots {
    final slots = {..._allDefaultSlots, ..._selectedTimeSlots}.toList();
    slots.sort((a, b) => FirestoreService.timeSlotMinutes(a)
        .compareTo(FirestoreService.timeSlotMinutes(b)));
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final now = IstClock.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    return ResponsiveCenter(child: Scaffold(
      appBar: AppBar(
        title: const Text('Manage Your Schedule'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryTeal),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month Title Header
                  Text(
                    '${_monthNames[now.month - 1]} ${now.year}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Horizontal Date Picker Bar for Current Month
                  SizedBox(
                    height: 75,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: daysInMonth,
                      itemBuilder: (context, index) {
                        final date = DateTime(now.year, now.month, index + 1);
                        final isSelected =
                            _formatDateKey(date) == _formatDateKey(_selectedDate);

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDate = date;
                            });
                            _loadScheduleForSelectedDate();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 60,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryTeal : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryTeal
                                    : AppColors.lineStrong,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primaryTeal
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _getWeekdayName(date.weekday),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white70
                                        : AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Selected Date Card Header
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.event_available_rounded,
                                    color: _isAvailableOnDate
                                        ? AppColors.verified
                                        : AppColors.danger),
                                const SizedBox(width: 8),
                                Text(
                                  '${_selectedDate.day} ${_monthNames[_selectedDate.month - 1].substring(0, 3)} ${_selectedDate.year}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isAvailableOnDate
                                    ? AppColors.verifiedSoft
                                    : AppColors.dangerSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _isAvailableOnDate ? 'Available' : 'Day Off',
                                style: TextStyle(
                                  color: _isAvailableOnDate
                                      ? AppColors.verifiedDark
                                      : AppColors.danger,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Switch ListTile for Availability / Day Off
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Accept Appointments on This Date',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: const Text(
                            'Enable or disable appointment bookings for this date.',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _isAvailableOnDate,
                          activeColor: Colors.white,
                          trackColor: WidgetStateProperty.resolveWith((states) =>
                              states.contains(WidgetState.selected)
                                  ? AppColors.verified
                                  : null),
                          onChanged: (val) {
                            setState(() => _isAvailableOnDate = val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // If Available, show Time Slots Selector
                  if (_isAvailableOnDate) ...[
                    const Text(
                      'Manage Time Slots',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select the time slots you want to make available for patient bookings.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),

                    LayoutBuilder(builder: (context, box) {
                    final cols = box.maxWidth >= 600 ? 3 : 2;
                    final w = (box.maxWidth - 10 * (cols - 1)) / cols;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _visibleSlots.map((slot) {
                        final isSelected = _selectedTimeSlots.contains(slot);
                        // overlaps a slot that is already on: can't be switched on
                        final blocked = !isSelected && _conflictWith(slot) != null;
                        return Tooltip(
                          message: blocked
                              ? 'Overlaps with ${_conflictWith(slot)}'
                              : '',
                          child: _SlotTile(
                            width: w,
                            label: slot,
                            selected: isSelected,
                            blocked: blocked,
                            onSelected: (selected) {
                              if (selected) {
                                final conflict = _conflictWith(slot);
                                if (conflict != null) {
                                  _warnOverlap(slot, conflict);
                                  return;
                                }
                              }
                              setState(() {
                                if (selected) {
                                  _selectedTimeSlots.add(slot);
                                } else {
                                  _selectedTimeSlots.remove(slot);
                                }
                              });
                            },
                          ),
                        );
                      }).toList(),
                    );
                    }),

                    const SizedBox(height: 20),

                    // Custom time slot (pick start and end)
                    OutlinedButton.icon(
                      onPressed: _addCustomSlot,
                      icon: const Icon(Icons.add_alarm_rounded),
                      label: const Text('Add my own slot (e.g. 02:00 PM - 03:00 PM)'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48)),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Save Schedule Button
                  ElevatedButton.icon(
                    onPressed: _saveSchedule,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(
                      'Save Schedule for ${_selectedDate.day}/${_selectedDate.month}',
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    ));
  }

  String _getWeekdayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(weekday - 1) % 7];
  }
}

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

/// A time slot button: fixed width (two per row), tick when switched on.
class _SlotTile extends StatelessWidget {
  final double width;
  final String label;
  final bool selected;
  final bool blocked;
  final ValueChanged<bool> onSelected;
  const _SlotTile({
    required this.width,
    required this.label,
    required this.selected,
    required this.blocked,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? Colors.white
        : (blocked ? AppColors.muted : AppTheme.textDark);
    return SizedBox(
      width: width,
      height: 44,
      child: Material(
        color: selected ? AppTheme.primaryTeal : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: selected ? AppTheme.primaryTeal : AppColors.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelected(!selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        decoration:
                            blocked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
