import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../utils/ist_clock.dart';

class TherapistScheduleScreen extends StatefulWidget {
  final UserModel therapist;

  const TherapistScheduleScreen({
    super.key,
    required this.therapist,
  });

  @override
  State<TherapistScheduleScreen> createState() =>
      _TherapistScheduleScreenState();
}

class _TherapistScheduleScreenState extends State<TherapistScheduleScreen> {
  DateTime _selectedDate = IstClock.now();
  bool _isAvailableOnDate = true;
  List<String> _selectedTimeSlots = [
    '08:00 AM',
    '09:00 AM',
    '10:00 AM',
    '11:00 AM',
    '02:00 PM',
    '04:00 PM',
    '06:00 PM'
  ];

  bool _isLoading = false;
  final TextEditingController _customTimeController = TextEditingController();

  final List<String> _allDefaultSlots = [
    '08:00 AM',
    '09:00 AM',
    '10:00 AM',
    '11:00 AM',
    '12:00 PM',
    '01:00 PM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
    '05:00 PM',
    '06:00 PM',
    '07:00 PM',
    '08:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _loadScheduleForSelectedDate();
  }

  @override
  void dispose() {
    _customTimeController.dispose();
    super.dispose();
  }

  String _formatDateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadScheduleForSelectedDate() async {
    setState(() => _isLoading = true);
    final dateKey = _formatDateKey(_selectedDate);

    final data = await FirestoreService.getDoctorDateSchedule(
      doctorUid: widget.therapist.uid,
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
        setState(() {
          _isAvailableOnDate = true;
          _selectedTimeSlots = [
            '08:00 AM',
            '09:00 AM',
            '10:00 AM',
            '11:00 AM',
            '02:00 PM',
            '04:00 PM',
            '06:00 PM'
          ];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSchedule() async {
    setState(() => _isLoading = true);
    final dateKey = _formatDateKey(_selectedDate);

    try {
      await FirestoreService.saveDoctorDateSchedule(
        doctorUid: widget.therapist.uid,
        dateKey: dateKey,
        isAvailable: _isAvailableOnDate,
        timeSlots: _visibleSlots.where(_selectedTimeSlots.contains).toList(), // in time order
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAvailableOnDate
                ? 'Physio schedule saved for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} (${_selectedTimeSlots.length} slots)'
                : 'Marked as BUSY for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
          ),
          backgroundColor: AppColors.primary,
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

  void _addCustomSlot() {
    final text = _customTimeController.text.trim();
    if (text.isEmpty) return;
    final slot = FirestoreService.normalizeTimeSlot(text);
    if (slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a time like 08:30 PM or 20:30'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() {
      if (!_selectedTimeSlots.contains(slot)) _selectedTimeSlots.add(slot);
      _customTimeController.clear();
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
    const primarySky = AppColors.primary;

    return ResponsiveCenter(child: Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        title: const Text('My Monthly Schedule'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.darkNavy,
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primarySky),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Month Calendar (${now.month}/${now.year})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy,
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
                              color: isSelected
                                  ? primarySky
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? primarySky
                                    : AppColors.lineStrong,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: primarySky.withValues(alpha: 0.3),
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
                                        : AppTheme.darkNavy,
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
                                  'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.darkNavy,
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
                                _isAvailableOnDate ? 'AVAILABLE' : 'BUSY / OFF',
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
                            'Available for Therapy Visits on this Date',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            _isAvailableOnDate
                                ? 'Patients can book home therapy sessions on this date'
                                : 'Marked BUSY (No bookings allowed)',
                            style: const TextStyle(fontSize: 12),
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
                      'Available Therapy Time Slots',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap time slots to toggle availability for this date:',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _visibleSlots.map((slot) {
                        final isSelected = _selectedTimeSlots.contains(slot);
                        return FilterChip(
                          label: Text(slot),
                          selected: isSelected,
                          selectedColor: primarySky,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.darkNavy,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedTimeSlots.add(slot);
                              } else {
                                _selectedTimeSlots.remove(slot);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // Custom Time Slot Addition
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customTimeController,
                            decoration: const InputDecoration(
                              hintText: 'Add custom slot (e.g. 08:30 PM)',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primarySky,
                            minimumSize: const Size(80, 48),
                          ),
                          onPressed: _addCustomSlot,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Save Schedule Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primarySky,
                      minimumSize: const Size(double.infinity, 50),
                    ),
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
