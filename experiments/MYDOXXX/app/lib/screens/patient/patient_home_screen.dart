import '../../services/app_database.dart';
import '../../utils/safe_cast.dart';
import '../../utils/maps_navigation.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/sos_tracker_dialog.dart';
import '../../services/push_service.dart';
import '../../widgets/incoming_call_listener.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/appointment_rules.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/emergency_questionnaire_modal.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';
import 'book_care_physician_screen.dart';
import 'book_doctor_screen.dart';
import 'book_nurse_screen.dart';
import 'book_technician_screen.dart';
import 'book_therapist_screen.dart';
import 'edit_patient_profile_screen.dart';
import 'my_bookings_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/area_picker_sheet.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../utils/display_names.dart';
import '../../widgets/active_emergency_banner.dart';
import '../../services/images_master.dart';
import '../../widgets/master_image.dart';
import '../../widgets/circle_image.dart';
import '../../widgets/unread_badge.dart';
import '../../services/chat_access_service.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/test_suggestion_ui.dart';
import '../../widgets/app_search_field.dart';
import '../../services/app_search.dart';

class PatientHomeScreen extends StatefulWidget {
  final UserModel patient;

  const PatientHomeScreen({
    super.key,
    required this.patient,
  });

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  final AuthService _authService = AuthService();
  late UserModel _patient;

  int _selectedIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late IncomingCallWatcher _callWatcher;
  String _currentLocation = 'Pune';
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    PushService.registerForUser(widget.patient.uid);
    PushService.openSignal.addListener(_onPushTap);
    _callWatcher = IncomingCallWatcher(
      contextProvider: () => context,
      uid: widget.patient.uid,
      userName: () => _patient.name,
    )..start();
    FirestoreService.seedInitialDoctorsIfEmpty();
    _fetchLiveLocation();
    // Tests a doctor suggested and the patient has not booked: remind them
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TestSuggestionPrompt.checkAndShow(context,
            patientUid: _patient.uid, patient: _patient);
      }
    });
    // Mark no-show providers absent and close sessions left open
    FirestoreService.runPunctualityChecks(patientUid: _patient.uid);
  }

  @override
  void dispose() {
    PushService.openSignal.removeListener(_onPushTap);
    _callWatcher.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveLocation() async {
    setState(() => _isLoadingLocation = true);
    final location = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _currentLocation = location;
        _isLoadingLocation = false;
      });
    }
  }

  void _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openEditProfile() async {
    final updatedUser = await Navigator.of(context).push<UserModel>(
      MaterialPageRoute(
        builder: (_) => EditPatientProfileScreen(patient: _patient),
      ),
    );

    if (updatedUser != null && mounted) {
      setState(() {
        _patient = updatedUser;
      });
    }
  }

  /// The pencil next to the page title changes the name shown on the profile
  /// card; "Modify Profile Data" below opens the full form.
  Future<void> _editProfileTitle() async {
    final c = TextEditingController(text: _patient.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit profile name'),
        content: TextField(
          controller: c,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _patient.name || !mounted) {
      return;
    }
    try {
      final p = _patient;
      final updated = await _authService.updatePatientProfile(
        uid: p.uid,
        name: name,
        phone: p.phone ?? '',
        age: p.age ?? '',
        bloodGroup: p.bloodGroup ?? 'O+',
        weight: p.weight ?? '',
        allergy: p.allergy ?? '',
        homeAddress: p.homeAddress ?? '',
        emergencyContact: p.emergencyContact ?? '',
        preferredDoctorUids: p.preferredDoctorUids,
        preferredDoctorNames: p.preferredDoctorNames,
      );
      if (mounted) {
        setState(() => _patient = updated);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile Updated Successfully')));
      }
    } catch (_) {}
  }

  void _showLocationSelectorModal() async {
    final areas = await FirestoreService.getLocationMaster();
    if (!mounted) return;
    final picked = await AreaPickerSheet.show(context,
        areas: areas, selected: _currentLocation);
    if (picked == null || !mounted) return;
    if (picked == AreaPickerSheet.useGps) {
      _fetchLiveLocation();
    } else {
      setState(() => _currentLocation = picked);
    }
  }

  void _showSetFavoriteDoctorDialog() async {
    final doctors = await AppDatabase.instance
        .collection('doctors')
        .where('isVerified', isEqualTo: true)
        .get();

    if (!mounted) return;

    final docList = doctors.docs.map((d) {
      final map = d.data();
      map['uid'] = d.id;
      return map;
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.star_rounded,
                    color: AppColors.warningBright, size: 28),
                SizedBox(width: 8),
                Expanded(
                    child: Text('Favorite Doctor per Category',
                        style: TextStyle(fontSize: 18))),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Pick one favorite doctor for each medical category:',
                      style:
                          TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(height: 16),
                  ...[
                    'General Physician',
                    'Cardiologist',
                    'Pediatrician',
                    'Neurologist',
                    'Dermatologist',
                    'Orthopedic'
                  ].map((cat) {
                    final currentFavName =
                        _patient.favoriteDoctorNames?[cat] ?? 'None Selected';

                    final categoryDocs = docList
                        .where((d) =>
                            (d['category'] as String?)?.toLowerCase() ==
                            cat.toLowerCase())
                        .toList();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 4),
                          Text('Current Favorite: $currentFavName',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.primaryTeal,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            menuMaxHeight: 320,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8)),
                            hint: Text(
                                categoryDocs.isEmpty
                                    ? 'No $cat available'
                                    : 'Select $cat Doctor',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                            items: categoryDocs.map((doc) {
                              final name = doc['name'] ?? 'Doctor';
                              final uid = doc['uid'] ?? '';
                              return DropdownMenuItem<String>(
                                value: '$uid|$name',
                                child: Text(name,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) async {
                              if (val != null) {
                                final parts = val.split('|');
                                await FirestoreService
                                    .savePatientFavoriteDoctor(
                                  patientUid: _patient.uid,
                                  category: cat,
                                  doctorUid: parts[0],
                                  doctorName: parts[1],
                                );

                                final updatedModel =
                                    await AuthService().getCurrentUserModel();
                                if (updatedModel != null && mounted) {
                                  setState(() => _patient = updatedModel);
                                  setDialogState(() {});
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleSosEmergencyTrigger() async {
    // Ask first: an emergency request alerts hospitals, doctors and ambulances
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.danger, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('Book an emergency?')),
          ],
        ),
        content: const Text(
          'Are you sure you want to book an emergency?\n\nThis alerts nearby hospitals, doctors and ambulances right away. Only continue if this is a real emergency.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, book emergency'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    // Only another open emergency blocks a new one. An urgent home visit or a
    // consultation in progress does not stop the patient asking for help.
    final hasActiveConsultation =
        await FirestoreService.patientHasActiveSos(_patient.uid);

    if (hasActiveConsultation) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.warning, size: 28),
              SizedBox(width: 8),
              Expanded(child: Text('Emergency In Progress')),
            ],
          ),
          content: const Text(
            'Your emergency request is already in progress. Please wait for it to complete before requesting another.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EmergencyQuestionnaireModal(
        patient: _patient,
        currentLocation: _currentLocation,
        onSosSubmitted: (appointmentId) {
          _showSosPipelineTrackerModal(appointmentId);
        },
      ),
    );
  }

  void _showSosPipelineTrackerModal(String appointmentId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SosTrackerDialog(appointmentId: appointmentId),
    );
  }

  void _openBookDoctor({String? category, bool isEmergency = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDoctorScreen(
          patient: _patient,
          initialCategory: category,
          initialLocationArea: _currentLocation,
          isUrgentEmergency: isEmergency,
        ),
      ),
    );
  }

  void _openBookNurse() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookNurseScreen(patient: _patient),
      ),
    );
  }

  void _openBookTechnician({String? testName}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookTechnicianScreen(
          patient: _patient,
          initialTestName: testName,
        ),
      ),
    );
  }

  void _openBookTherapist() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookTherapistScreen(
          patient: _patient,
        ),
      ),
    );
  }

  /// Search index, loaded the first time the patient searches.
  Future<List<SearchItem>>? _searchIndex;

  Widget _buildSearchResults() {
    return FutureBuilder<List<SearchItem>>(
      future: _searchIndex,
      builder: (context, snap) {
        // the main services match at once, the rest once loaded
        final results = AppSearch.filter(
            _searchQuery, snap.data ?? AppSearch.services,
            limit: 12);
        return Container(
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    snap.connectionState == ConnectionState.waiting
                        ? 'Searching…'
                        : 'Nothing found for "$_searchQuery".',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              for (final r in results)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(_searchIcon(r.kind),
                        color: AppColors.primary, size: 18),
                  ),
                  title: Text(r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.ink)),
                  subtitle: r.subtitle.isEmpty
                      ? null
                      : Text(r.subtitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.muted),
                  onTap: () => _openSearchItem(r),
                ),
            ],
          ),
        );
      },
    );
  }

  static IconData _searchIcon(SearchKind kind) => switch (kind) {
        SearchKind.service => Icons.apps_rounded,
        SearchKind.specialty => Icons.medical_services_outlined,
        SearchKind.doctor => Icons.person_outline_rounded,
        SearchKind.labTest => Icons.science_outlined,
        SearchKind.therapy => Icons.self_improvement_rounded,
        SearchKind.careService => Icons.add_home_work_outlined,
      };

  void _openSearchItem(SearchItem r) {
    FocusScope.of(context).unfocus();
    switch (r.kind) {
      case SearchKind.specialty:
      case SearchKind.doctor:
        _openBookDoctor(category: r.target.isEmpty ? null : r.target);
      case SearchKind.labTest:
        _openBookTechnician(testName: r.target);
      case SearchKind.therapy:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BookTherapistScreen(
                patient: _patient, initialTherapyName: r.target)));
      case SearchKind.careService:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BookCarePhysicianScreen(patient: _patient)));
      case SearchKind.service:
        switch (r.target) {
          case 'nurse':
            _openBookNurse();
          case 'technician':
            _openBookTechnician();
          case 'therapist':
            _openBookTherapist();
          case 'care_physician':
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookCarePhysicianScreen(patient: _patient)));
          case 'sos':
            _handleSosEmergencyTrigger();
          default:
            _openBookDoctor();
        }
    }
  }

  /// Bookings is a tab (so the bar shows it selected); [initialTab] picks
  /// Scheduled / Urgent / SOS inside it.
  int _bookingsTab = 0;
  void _openMyBookings({int initialTab = 0}) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      _bookingsTab = initialTab;
      _selectedIndex = 1;
    });
  }

  /// A notification in the phone's panel was tapped: come back to the home
  /// tab, where the bell opens the notifications list.
  void _onPushTap() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
        child: PopScope(
            // Back from Bookings / Chat / Profile returns to Home, not out of the app
            canPop: _selectedIndex == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _selectedIndex = 0);
            },
            child: Scaffold(
              backgroundColor: AppTheme.bgLight,
              body: switch (_selectedIndex) {
                1 => MyBookingsScreen(
                    key: ValueKey('bookings$_bookingsTab'),
                    patient: _patient,
                    initialTab: _bookingsTab,
                  ),
                2 => SafeArea(child: _buildChatTab()),
                3 => SafeArea(child: _buildProfileTab()),
                _ => SafeArea(
                    child: RefreshIndicator(
                        onRefresh: _fetchLiveLocation,
                        child: _buildHomeTab())),
              },
              // the Chat tab shows how many chats have unread messages
              bottomNavigationBar: StreamBuilder<int>(
                stream: _streams.get('unreadChats',
                    () => ChatAccessService.unreadChats(_patient.uid)),
                builder: (context, unread) => AppBottomNav(
                  currentIndex: _selectedIndex,
                  items: [
                    const AppNavItem(Icons.home_rounded, 'Home'),
                    const AppNavItem(Icons.calendar_month_rounded, 'Bookings'),
                    AppNavItem(Icons.chat_bubble_rounded, AppStrings.chat,
                        badge: unread.data ?? 0),
                    const AppNavItem(Icons.person_rounded, 'Profile'),
                  ],
                  onTap: (index) => setState(() {
                    if (index == 1) _bookingsTab = 0;
                    _selectedIndex = index;
                  }),
                ),
              ),
            )));
  }

  /// Main Dashboard Home Tab matching exact Healthcare Theme Screenshot
  /// "In 25 min", "In 3 h 10 min", "Tomorrow", "In 4 days".
  static String _countdownLabel(DateTime at) {
    final d = at.difference(DateTime.now());
    if (d.inMinutes < 1) return 'Starting now';
    if (d.inMinutes < 60) return 'In ${d.inMinutes} min';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      return m == 0 ? 'In ${d.inHours} h' : 'In ${d.inHours} h $m min';
    }
    final days = d.inDays;
    return days == 1 ? 'Tomorrow' : 'In $days days';
  }

  /// Names of the real doctor specialities. Nurse / technician / therapist
  /// bookings keep a qualification or test name in the same field, which must
  /// not show up as a "book again" doctor speciality.
  Future<Set<String>>? _doctorSpecialties;
  Future<Set<String>> _loadDoctorSpecialties() async {
    try {
      final snap =
          await AppDatabase.instance.collection('category_doctors').get();
      return {
        for (final d in snap.docs)
          (d.data()['name'] ?? d.id).toString().trim().toLowerCase(),
      };
    } catch (_) {
      return <String>{};
    }
  }

  /// Quick repeat booking: the specialities this patient booked before.
  Widget _buildBookAgain() {
    _doctorSpecialties ??= _loadDoctorSpecialties();
    return FutureBuilder<Set<String>>(
      future: _doctorSpecialties,
      builder: (context, specSnap) => _bookAgainChips(specSnap.data ?? {}),
    );
  }

  Widget _bookAgainChips(Set<String> specialties) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streams.get('bookings',
          () => FirestoreService.getPatientBookingsStream(_patient.uid)),
      builder: (context, snap) {
        final seen = <String>{};
        for (final b in (snap.data ?? const <Map<String, dynamic>>[])
            .reversed) {
          final c = (b['doctorCategory'] ?? '').toString().trim();
          if (c.isEmpty || AppointmentRules.isSos(b)) continue;
          if (!specialties.contains(c.toLowerCase())) continue;
          seen.add(c);
          if (seen.length == 3) break;
        }
        if (seen.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Book again',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in seen)
                    ActionChip(
                      avatar: const Icon(Icons.replay_rounded,
                          size: 16, color: AppColors.primary),
                      label: Text(c),
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.ink),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.line),
                      onPressed: () => _openBookDoctor(category: c),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Header Bar (Red Heart + Healthcare + Location Pin + Notification Bell)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'MyDox',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Location Pin + City Dropdown
                  GestureDetector(
                    onTap: _showLocationSelectorModal,
                    child: Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: AppTheme.textMuted, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _isLoadingLocation ? 'Locating...' : _currentLocation,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.keyboard_arrow_down_rounded,
                            color: AppTheme.textMuted, size: 18),
                      ],
                    ),
                  ),
                ],
              ),

              // Notification Bell Icon Button
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                    )
                  ],
                ),
                child: NotificationBell(
                  uid: _patient.uid,
                  collection: 'patients',
                  forPatient: true,
                  bookings: _streams.get(
                      'bookings',
                      () => FirestoreService.getPatientBookingsStream(
                          _patient.uid)),
                  onOpenItem: _openMyBookings,
                ),
              ),
            ],
          ),

          // Running SOS (its window was closed): blinking red way back to it
          StreamBuilder<Map<String, dynamic>?>(
            stream: _streams.get('active_sos',
                () => FirestoreService.patientActiveSosStream(_patient.uid)),
            builder: (context, snap) {
              final sos = snap.data;
              if (sos == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ActiveEmergencyBanner(
                  status: (sos['status'] ?? '').toString(),
                  onTap: () => _showSosPipelineTrackerModal(
                      sos['appointmentId'].toString()),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Emergency SOS: first thing on screen, always one tap away
          // 6. Emergency SOS Help Card Banner (Red Coral Gradient)
          GestureDetector(
            onTap: _handleSosEmergencyTrigger,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: AppTheme.emergencyGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.heartRed.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_in_talk_rounded,
                              color: AppTheme.heartRed, size: 20),
                          Text(
                            'SOS',
                            maxLines: 1,
                            style: TextStyle(
                              color: AppTheme.heartRed,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency help',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Request assistance',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Tests the doctor suggested and the patient has not booked yet
          TestSuggestionHomeList(patient: _patient),

          const SizedBox(height: 24),

          // 2. Large Headline Greeting
          const Text(
            'How can we help you today?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkNavy,
            ),
          ),

          const SizedBox(height: 18),

          // 3. Search: type or speak; finds services, specialities,
          // doctors, lab tests, therapies and home-care services
          AppSearchField(
            controller: _searchController,
            hint: 'Search doctors, tests, therapies…',
            onChanged: (val) {
              _searchIndex ??= AppSearch.loadIndex();
              setState(() => _searchQuery = val.trim());
            },
          ),
          if (_searchQuery.isNotEmpty) _buildSearchResults(),

          const SizedBox(height: 20),

          // 4. Hero Banner Card ("Find a doctor")
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primarySoft, AppColors.primaryTint],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Find a doctor',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () => _openBookDoctor(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentTeal,
                          minimumSize: const Size(160, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Book appointment'),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_ios_rounded, size: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),
                // Doctor photo from images_master (Firebase)
                CircleFrame(
                  size: 104,
                  child: MasterImage(
                    imageKey: ImagesMaster.banner('home'),
                    fit: BoxFit.cover,
                    placeholder: const Center(
                      child: Icon(
                        Icons.medical_services_rounded,
                        size: 40,
                        color: AppTheme.accentTeal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 5. 6 Pastel Service Box Cards (2 x 3 Grid matching screenshot)
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // 3 per row; tall enough for a two-line label at any font size
            gridDelegate: Responsive.grid(context,
                minTileWidth: 80,
                tileHeight: 124,
                spacing: 12,
                minColumns: 3,
                maxColumns: 3),
            children: [
              _buildServiceCard(
                label: 'Doctors',
                icon: Icons.person_search_rounded,
                bgColor: AppTheme.pastelBlue,
                iconColor: const Color(0xFF0284C7),
                onTap: () => _openBookDoctor(),
              ),
              _buildServiceCard(
                label: 'Nurses',
                icon: Icons.local_hospital_rounded,
                bgColor: AppTheme.pastelGreen,
                iconColor: const Color(0xFF16A34A),
                onTap: () => _openBookNurse(),
              ),
              _buildServiceCard(
                label: 'Technician',
                icon: Icons.science_rounded,
                bgColor: AppTheme.pastelPurple,
                iconColor: const Color(0xFF9333EA),
                onTap: () => _openBookTechnician(),
              ),
              _buildServiceCard(
                label: 'Therapist',
                icon: Icons.medication_rounded,
                bgColor: AppTheme.pastelPink,
                iconColor: AppColors.danger,
                onTap: () => _openBookTherapist(),
              ),
              _buildServiceCard(
                label: 'Care Physician',
                icon: Icons.add_home_work_outlined,
                bgColor: AppTheme.pastelMint,
                iconColor: const Color(0xFF0D9488),
                // care physician home visit (services and prices from Firestore)
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        BookCarePhysicianScreen(patient: _patient))),
              ),
              _buildServiceCard(
                label: 'Ambulance',
                icon: Icons.airport_shuttle_rounded,
                bgColor: AppTheme.pastelYellow,
                iconColor: const Color(0xFFD97706),
                onTap: () => _openBookDoctor(isEmergency: true),
              ),
            ],
          ),

          const SizedBox(height: 20),


          const SizedBox(height: 28),

          // 7. Realtime Stream of Patient's Upcoming Appointment
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Upcoming Appointments',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy,
                ),
              ),
              GestureDetector(
                onTap: _openMyBookings,
                child: const Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryTeal,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get('bookings',
                () => FirestoreService.getPatientBookingsStream(_patient.uid)),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return LoadErrorView(
                    error: snapshot.error, what: 'your bookings');
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonCard();
              }

              final bookings = snapshot.data ?? [];

              if (bookings.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_available_rounded,
                            color: AppTheme.primaryTeal),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No Upcoming Appointments',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Book a doctor near you, anytime',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _openBookDoctor(),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(80, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('Book'),
                      ),
                    ],
                  ),
                );
              }

              final upcoming = bookings
                  .where((b) => AppointmentRules.isUpcoming(b))
                  .toList()
                ..sort(AppointmentRules.compareByStart);
              final latest = upcoming.isNotEmpty ? upcoming.first : bookings.last;
              final startsAt = AppointmentRules.start(latest);
              final docName = latest['doctorName'] ?? 'Doctor';
              final category = latest['doctorCategory'] ?? 'Specialist';
              final date = latest['date'] ?? '';
              final time = latest['time'] ?? '';
              final mode = latest['consultationType'] ?? 'Clinic/Visit';
              final int price = toNum(latest['price'])?.toInt() ?? 0;

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppTheme.pastelBlue,
                          child: const Icon(Icons.medical_services_rounded,
                              color: AppTheme.primaryTeal, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                docName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy,
                                ),
                              ),
                              Text(
                                '$category • $mode (₹$price)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _openMyBookings(
                              initialTab: AppointmentRules.isSos(latest)
                                  ? 2
                                  : AppointmentRules.isUrgent(latest)
                                      ? 1
                                      : 0),
                          child: const Text(
                            'View Details',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryTeal,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // How soon: "In 2 h 15 min", so the patient needn't work it out
                    if (startsAt != null && startsAt.isAfter(DateTime.now())) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                _countdownLabel(startsAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Date and Time Box
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.access_time_rounded,
                              size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (latest['hospital'] != null &&
                        latest['hospital'].toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          minimumSize: const Size(double.infinity, 38),
                        ),
                        onPressed: () {
                          final hospital =
                              (latest['hospital'] ?? 'Doctor Clinic')
                                  .toString();
                          final dLat =
                              toNum(latest['doctorLat'])?.toDouble();
                          final dLng =
                              toNum(latest['doctorLng'])?.toDouble();
                          // saved hospital coordinates (looked up if not on the booking)
                          MapsNavigation.toHospitalWithHint(context, hospital,
                              lat: dLat, lng: dLng);
                        },
                        icon: const Icon(Icons.directions_outlined, size: 16),
                        label:
                            Text('Navigate to Clinic (${latest['hospital']})'),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          _buildBookAgain(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleImage(
              imageKey: ImagesMaster.service(label),
              size: 60,
              icon: icon,
              iconColor: iconColor,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openChatWithDoctor(String doctorUid, String doctorName) {
    final chatId = '${_patient.uid}_$doctorUid';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          currentUserId: _patient.uid,
          currentUserName: _patient.name,
          peerName: doctorName,
          peerRole: 'Doctor',
        ),
      ),
    );
  }

  /// Patient Records & Consulted Doctors Tab
  /// Chat tab: only doctors the patient has consulted. Chat is open from
  /// the start of a consultation until 24 hours after it.
  Widget _buildChatTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streams.get(
          'consulted',
          () =>
              FirestoreService.getPatientConsultedDoctorsStream(_patient.uid)),
      builder: (context, snapshot) {
        final doctors = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Text(AppStrings.chat,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink)),
            const SizedBox(height: 4),
            const Text(
              'Doctors you have consulted. Chat opens when a consultation ends and is free for 24 hours, with 10 messages.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (doctors.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Text(
                    'No consultations yet. Doctors appear here once a consultation has started.',
                    style: TextStyle(color: AppColors.muted)),
              )
            else
              for (final doc in doctors) _consultedDoctorTile(doc),
          ],
        );
      },
    );
  }

  Widget _consultedDoctorTile(Map<String, dynamic> doc) {
    final dUid = (doc['doctorUid'] ?? '').toString();
    final dName = (doc['doctorName'] ?? 'Doctor').toString();
    final dCat = (doc['doctorCategory'] ?? 'Specialist').toString();
    final open = doc['chatOpen'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          UnreadBadge(
            chatId: '${_patient.uid}_$dUid',
            uid: _patient.uid,
            child: const CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primarySoft,
              child: Icon(Icons.medical_services_rounded,
                  color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(DisplayNames.doctor(dName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.ink)),
                  ),
                  const SizedBox(width: 6),
                  OnlineDot(uid: dUid),
                ]),
                Text(
                  open ? dCat : '$dCat · recharge to chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            // always opens: after the free 24 hours the chat offers the recharge
            onPressed: () => _openChatWithDoctor(dUid, dName),
            icon: Icon(
                open
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.bolt_rounded,
                size: 16),
            label: Text(open ? AppStrings.chat : 'Recharge'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              iconColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Patient Profile Tab View
  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Profile & Health Info',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy,
                ),
              ),
              IconButton(
                tooltip: 'Edit profile name',
                icon:
                    const Icon(Icons.edit_rounded, color: AppTheme.primaryTeal),
                onPressed: _editProfileTitle,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // MedCoins: money returned to the wallet (1 MedCoin = ₹1)
          StreamBuilder<int>(
            stream: ChatAccessService.walletBalance(_patient.uid),
            builder: (context, snap) {
              final coins = snap.data ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('MedCoins wallet',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkNavy)),
                  ),
                  Text('$coins MedCoins',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.primary)),
                ]),
              );
            },
          ),

          // User Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                SafeAvatar(
  imageUrl: _patient.profilePicUrl,
  radius: 32,
  backgroundColor: Colors.white.withValues(alpha: 0.2),
  fallback: const Icon(Icons.person, color: Colors.white, size: 40),
),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _patient.name.isNotEmpty
                            ? _patient.name
                            : 'Patient Name',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _patient.email,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _patient.phone ?? 'No phone added',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Favorite Doctors per Category Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warningTint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.warningBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: AppColors.warningBright, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Favorite Doctors per Category',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Choose one preferred doctor for Cardiology, Pediatrics, etc.',
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    minimumSize: const Size(0, 38),
                  ),
                  onPressed: _showSetFavoriteDoctorDialog,
                  child: const Text('Manage'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Health Details Grid Title
          const Text(
            'Personal Health Stats',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkNavy,
            ),
          ),

          const SizedBox(height: 12),

          // Health Metrics Grid Cards
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  title: 'Blood Group',
                  value: _patient.bloodGroup ?? 'Not set',
                  icon: Icons.bloodtype_outlined,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  title: 'Age',
                  value: _patient.age != null && _patient.age!.isNotEmpty
                      ? '${_patient.age} Yrs'
                      : 'Not set',
                  icon: Icons.cake_outlined,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  title: 'Weight',
                  value: _patient.weight != null && _patient.weight!.isNotEmpty
                      ? '${_patient.weight} kg'
                      : 'Not set',
                  icon: Icons.monitor_weight_outlined,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Detailed List Cards
          _buildDetailTile(
            title: 'Allergies',
            value: _patient.allergy ?? 'None reported',
            icon: Icons.warning_amber_rounded,
          ),

          _buildDetailTile(
            title: 'Home Address',
            value: _patient.homeAddress ?? 'Not specified',
            icon: Icons.home_outlined,
          ),

          _buildDetailTile(
            title: 'Emergency Contact',
            value: _patient.emergencyContact ?? 'Not specified',
            icon: Icons.contact_phone_outlined,
          ),

          const SizedBox(height: 28),

          // Edit Profile Action Button
          ElevatedButton.icon(
            onPressed: _openEditProfile,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modify Profile Data'),
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            label: const Text('Sign Out',
                style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.danger),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkNavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTile({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.primaryTeal, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkNavy,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
