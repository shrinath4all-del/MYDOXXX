import '../services/app_database.dart';
import '../services/lab_device.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/sos_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../services/location_service.dart';
import '../services/pricing_service.dart';
import '../utils/responsive.dart';
import '../constants/app_colors.dart';

class EmergencyQuestionnaireModal extends StatefulWidget {
  final UserModel patient;
  final String currentLocation;
  final Function(String appointmentId) onSosSubmitted;

  const EmergencyQuestionnaireModal({
    super.key,
    required this.patient,
    required this.currentLocation,
    required this.onSosSubmitted,
  });

  @override
  State<EmergencyQuestionnaireModal> createState() =>
      _EmergencyQuestionnaireModalState();
}

class _EmergencyQuestionnaireModalState
    extends State<EmergencyQuestionnaireModal> {
  int _currentStep = 0; // 0 = Categories, 1 = Questions, 2 = Transport Choice
  bool _isLoading = false;

  List<Map<String, dynamic>> _categories = [];
  bool _loadingCategories = true;

  Map<String, dynamic>? _selectedCategoryMap;
  Map<String, dynamic> _fetchedQuestionsMap = {};
  bool _loadingQuestions = false;

  final Map<String, String> _answers = {};
  bool _requiresAmbulance = true;

  @override
  void initState() {
    super.initState();
    _fetchEmergencyCategories();
  }

  Future<void> _fetchEmergencyCategories() async {
    try {
      final list = await FirestoreService.getEmergencyCategories();
      if (mounted) {
        setState(() {
          _categories = list;
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _categories = FirestoreService.defaultEmergencyCategories;
          _loadingCategories = false;
        });
      }
    }
  }

  List<String> _getOptionsForQuestion(String question, dynamic rawVal) {
    if (rawVal is List) {
      return rawVal.map((e) => e.toString()).toList();
    } else if (rawVal is bool) {
      return ['Yes', 'No'];
    } else if (rawVal is String && rawVal.contains(',')) {
      return rawVal.split(',').map((e) => e.trim()).toList();
    } else {
      final qLower = question.toLowerCase();
      if (qLower.contains('start') ||
          qLower.contains('time') ||
          qLower.contains('when')) {
        return ['<30 min', '30–60 min', '>1 hour'];
      }
      return ['Yes', 'No'];
    }
  }

  void _onCategorySelected(Map<String, dynamic> catItem) async {
    final catId = catItem['id'] ?? catItem['title'] ?? 'brain_stroke';

    setState(() {
      _selectedCategoryMap = catItem;
      _loadingQuestions = true;
      _currentStep = 1;
    });

    final qMap = await FirestoreService.getCategoryQuestions(catId);

    if (mounted) {
      setState(() {
        _fetchedQuestionsMap = qMap;
        _answers.clear();
        qMap.forEach((q, val) {
          final String qStr = q.toString();
          final List<String> opts = _getOptionsForQuestion(qStr, val);
          if (val is bool) {
            _answers[qStr] = val ? 'Yes' : 'No';
          } else if (val is String && opts.contains(val)) {
            _answers[qStr] = val;
          } else {
            _answers[qStr] = opts.first;
          }
        });
        _loadingQuestions = false;
      });
    }
  }

  IconData _getCategoryIconData(String catTitle) {
    final lower = catTitle.toLowerCase();
    if (lower.contains('cardiac') || lower.contains('heart')) {
      return Icons.favorite_rounded;
    } else if (lower.contains('brain') || lower.contains('stroke')) {
      return Icons.psychology_rounded;
    } else if (lower.contains('ortho') || lower.contains('trauma')) {
      return Icons.water_drop_rounded;
    } else if (lower.contains('chest') || lower.contains('breath')) {
      return Icons.air_rounded;
    } else if (lower.contains('preg') || lower.contains('obstet')) {
      return Icons.pregnant_woman_rounded;
    }
    return Icons.airport_shuttle_rounded;
  }

  Color _getCategoryColor(String catTitle) {
    final lower = catTitle.toLowerCase();
    if (lower.contains('cardiac')) return AppColors.danger;
    if (lower.contains('brain')) return AppColors.pink;
    if (lower.contains('ortho')) return AppColors.danger;
    if (lower.contains('chest')) return AppColors.dangerBright;
    if (lower.contains('preg')) return AppColors.purple;
    return AppColors.warning;
  }

  Future<void> _submitEmergencyRequest() async {
    setState(() => _isLoading = true);

    try {
      final docRef = AppDatabase.instance.collection('appointments').doc();
      final appointmentId = docRef.id;
      final sosOtp = SosService.newOtp(); // same code for ambulance + hospital

      final String catTitle =
          _selectedCategoryMap?['title'] ?? 'Critical Emergency';

      double patientLat = LocationService.defaultLat;
      double patientLng = LocationService.defaultLng;
      try {
        final pos = await LabLocation.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        patientLat = pos.latitude;
        patientLng = pos.longitude;
      } catch (_) {}

      // fee from Firestore app_settings/pricing; the server sets it again.
      // An emergency is never blocked because a price is missing.
      final sosFee = (await PricingService.load()).sosEmergencyFee;

      await docRef.set({
        'appointmentId': appointmentId,
        'patientUid': widget.patient.uid,
        'patientName': widget.patient.name,
        'patientPhone': widget.patient.phone ?? '',
        'doctorName': 'Hospital & Emergency Team',
        'doctorCategory': catTitle,
        'hospital': 'Nearest Verified Hospital',
        'date':
            '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
        'time': 'ASAP (Immediate SOS)',
        if (sosFee != null) 'price': sosFee,
        'locationName': widget.currentLocation,
        'patientLat': patientLat,
        'patientLng': patientLng,
        'consultationType': 'SOS Emergency Pipeline',
        'isUrgentEmergency': true,
        'emergencyCategory': catTitle,
        'questionAnswers': _answers,
        'requiresAmbulance': _requiresAmbulance,
        'status': 'Pending Hospital Acceptance',
        'otp': sosOtp,
        'ambulanceOtp': sosOtp,
        'hospitalOtp': sosOtp,
        'createdAt': DateTime.now().toIso8601String(),
        // whole process (hospital + doctor + ambulance) must finish in 5 min
        'sosExpiresAt':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      });

      if (!mounted) return;

      Navigator.pop(context); // Close Questionnaire Modal
      widget.onSosSubmitted(appointmentId); // Open Tracker Modal!
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ErrorMessages.of(e, action: 'send the SOS')),
            backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STEP 0: SELECT CATEGORY
            if (_currentStep == 0) ...[
              const Text(
                'What is happening?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy,
                ),
              ),
              const SizedBox(height: 16),

              if (_loadingCategories)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(30.0),
                    child: CircularProgressIndicator(color: AppColors.danger),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _categories.length,
                  gridDelegate: Responsive.grid(context,
                      minTileWidth: 140,
                      tileHeight: 104,
                      spacing: 12,
                      horizontalPadding: 48,
                      maxColumns: 3),
                  itemBuilder: (context, index) {
                    final item = _categories[index];
                    final String title = item['title'] ?? 'Emergency';
                    final IconData icon = _getCategoryIconData(title);
                    final Color color = _getCategoryColor(title);

                    return GestureDetector(
                      onTap: () => _onCategorySelected(item),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.lineStrong),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, color: color, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ]

            // STEP 1: QUESTIONNAIRE (Fetched from /emergency_categories/{id}/questions/questions_set)
            else if (_currentStep == 1) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.dangerLight),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getCategoryIconData(
                          _selectedCategoryMap?['title'] ?? ''),
                      color: _getCategoryColor(
                          _selectedCategoryMap?['title'] ?? ''),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCategoryMap?['title'] ?? 'Emergency',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedCategoryMap?['subtitle'] ??
                                'Will route to an emergency-ready hospital',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.dangerDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (_loadingQuestions)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: AppColors.danger),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _fetchedQuestionsMap.entries.map((entry) {
                    final String question = entry.key;
                    final dynamic rawVal = entry.value;

                    final List<String> options =
                        _getOptionsForQuestion(question, rawVal);

                    final String currentAns = _answers[question] ?? options.first;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: options.map((opt) {
                            final bool isSelected = currentAns == opt;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _answers[question] = opt;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.bgLight,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.lineStrong
                                          : AppColors.lineStrong,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    opt,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppTheme.darkNavy
                                          : AppColors.slate,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }).toList(),
                ),

              // Live Location & Phone Badge matching screenshot
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.successTint,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.successLight),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_rounded,
                        color: AppColors.successDark, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your live location (${widget.currentLocation}) and phone number go with the alert. Nothing to type.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.successDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () {
                  setState(() => _currentStep = 2);
                },
                child: const Text('Continue'),
              ),

              const SizedBox(height: 10),

              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                ),
                onPressed: () {
                  setState(() => _currentStep = 0);
                },
                child: const Text('Back'),
              ),
            ]

            // STEP 2: TRANSPORT CHOICE ("How will the patient reach the hospital?")
            else if (_currentStep == 2) ...[
              const Text(
                'If this is life-threatening, call 108 first. The steps below alert an ambulance, a hospital and a specialist at the same time.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
              ),

              const SizedBox(height: 14),

              // Category Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.dangerLight),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getCategoryIconData(
                          _selectedCategoryMap?['title'] ?? ''),
                      color: _getCategoryColor(
                          _selectedCategoryMap?['title'] ?? ''),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCategoryMap?['title'] ?? 'Emergency',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                          Text(
                            _selectedCategoryMap?['subtitle'] ??
                                'Will route to an emergency-ready hospital',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.dangerDeep),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'How will the patient reach the hospital?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy,
                ),
              ),

              const SizedBox(height: 4),

              const Text(
                'Either way, the hospital bed and the specialist are booked right now.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),

              const SizedBox(height: 16),

              // Option 1: Send an Ambulance
              GestureDetector(
                onTap: () {
                  setState(() => _requiresAmbulance = true);
                  _submitEmergencyRequest();
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.lineStrong, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warningTint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.airport_shuttle_rounded,
                            color: AppColors.warningBright, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send an ambulance to me',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Every crew nearby is alerted at once. You can track the ambulance live.',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Option 2: We will drive
              GestureDetector(
                onTap: () {
                  setState(() => _requiresAmbulance = false);
                  _submitEmergencyRequest();
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.lineStrong, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.directions_car_filled_rounded,
                            color: AppColors.blue, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'We will drive to the hospital',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'No crew is sent. The hospital keeps the bed and team ready for you.',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.danger),
                )
              else
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                  ),
                  onPressed: () {
                    setState(() => _currentStep = 1);
                  },
                  child: const Text('Back'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
