import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import 'dart:async';
import '../../widgets/area_picker_sheet.dart';
import '../../utils/form_utils.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../ambulance/ambulance_home_screen.dart';
import '../doctor/doctor_home_screen.dart';
import '../hospital/hospital_home_screen.dart';
import '../nurse/nurse_staffing_screen.dart';
import '../patient/patient_home_screen.dart';
import '../technician/technician_staffing_screen.dart';
import '../therapist/therapist_home_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../services/care_physician_service.dart';
import '../../services/nurse_staffing_service.dart';
import '../../services/technician_staffing_service.dart';
import '../care_physician/care_physician_home_screen.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../utils/ist_clock.dart';

class RegisterScreen extends StatefulWidget {
  final String initialRole;

  const RegisterScreen({
    super.key,
    this.initialRole = 'patient',
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late String _selectedRole;
  bool _isLoading = false;

  // Hospital's fixed location, captured once at registration
  Position? _hospitalPos;
  String _hospitalPlace = '';
  bool _capturingLocation = false;
  String? _locationError;

  /// Reads the hospital's live GPS position. It becomes the hospital's fixed
  /// location and can't be changed after registration.
  Future<void> _captureHospitalLocation() async {
    setState(() {
      _capturingLocation = true;
      _locationError = null;
    });
    try {
      if (!await LabLocation.isLocationServiceEnabled()) {
        throw Exception('Turn on location (GPS) on this device and try again.');
      }
      var perm = await LabLocation.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await LabLocation.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception(
            'Location permission is required to register a hospital. Please allow it and try again.');
      }
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );
      String place = '';
      try {
        place = await LocationService.getCurrentLocation();
      } catch (_) {}
      if (place == LocationService.notFound) place = '';
      if (!mounted) return;
      final area = _areaFromPlace(place);
      setState(() {
        _hospitalPos = pos;
        _hospitalPlace = place;
        _capturingLocation = false;
        // the area of the live location, when it is one of our areas
        if (area != null) _selectedHospitalArea = area;
        _areaNotDetected = area == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturingLocation = false;
        _locationError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Set when the live location's area is not one of our areas: the user
  /// picks it from the list.
  bool _areaNotDetected = false;

  /// Our area named in [place] ("Wakad, Pimpri-Chinchwad" -> "Wakad"), the
  /// longest match first; null when none.
  String? _areaFromPlace(String place) {
    final p = place.toLowerCase();
    if (p.trim().isEmpty) return null;
    final parts = p.split(',').map((e) => e.trim()).toSet();
    String? best;
    for (final a in _locationAreas) {
      final name = a.toLowerCase().split(',').first.trim();
      if (name.isEmpty) continue;
      final hit = parts.contains(name) ||
          RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(p);
      if (hit && (best == null || name.length > best.length)) best = a;
    }
    return best;
  }

  /// Hospital area: a searchable list (the live location fills it in).
  Future<void> _pickHospitalArea(FormFieldState<String> field) async {
    final picked = await AreaPickerSheet.show(context,
        areas: _locationAreas,
        selected: _selectedHospitalArea,
        showGps: false);
    if (picked == null || picked == AreaPickerSheet.useGps || !mounted) return;
    setState(() {
      _selectedHospitalArea = picked;
      _areaNotDetected = false;
    });
    field.didChange(picked);
  }

  // Common Auth Controllers

  // Hospital Fields Controllers
  final TextEditingController _hospitalNameController = TextEditingController();
  final TextEditingController _hospitalPhoneController = TextEditingController();
  final TextEditingController _hospitalAddressController = TextEditingController();

  // Ambulance Fields Controllers
  final TextEditingController _ambDriverController = TextEditingController();
  final TextEditingController _ambDriverLastController = TextEditingController();
  final TextEditingController _ambVehicleController = TextEditingController();
  final TextEditingController _ambCityController = TextEditingController();
  final TextEditingController _ambPhoneController = TextEditingController();

  // Doctor Fields Controllers
  final TextEditingController _doctorNameController = TextEditingController();
  final TextEditingController _doctorLastNameController = TextEditingController();
  final TextEditingController _doctorMobileController = TextEditingController();
  String? _selectedDoctorCategory;
  List<String> _doctorCategories = [];
  String? _selectedHospitalArea;
  List<String> _locationAreas = [];

  List<Map<String, dynamic>> _registeredHospitals = [];
  Map<String, dynamic>? _selectedHospitalMap;

  bool _loadingCategories = true;
  bool _mastersFailed = false;

  // Live Firestore listeners for the dropdowns above
  final List<StreamSubscription> _masterSubs = [];

  // Patient Fields Controllers
  final TextEditingController _patientNameController = TextEditingController();
  final TextEditingController _patientLastNameController = TextEditingController();
  final TextEditingController _patientPhoneController = TextEditingController();

  // the login: email and a password chosen here
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  final TextEditingController _patientAgeController = TextEditingController();

  // Technician Fields Controllers
  final TextEditingController _techNameController = TextEditingController();
  final TextEditingController _techLastNameController = TextEditingController();
  final TextEditingController _techPhoneController = TextEditingController();
  final TextEditingController _techOrgController = TextEditingController();
  final TextEditingController _techExpController = TextEditingController();
  final TextEditingController _techCityController = TextEditingController();
  // Firestore 'technician_qualifications' (live)
  String? _selectedTechQualification;
  List<String> _techQualifications = [];

  // Nurse Fields Controllers
  final TextEditingController _nurseNameController = TextEditingController();
  final TextEditingController _nurseLastNameController = TextEditingController();
  final TextEditingController _nursePhoneController = TextEditingController();
  final TextEditingController _nurseOrgController = TextEditingController();
  final TextEditingController _nurseExpController = TextEditingController();
  final TextEditingController _nurseCityController = TextEditingController();
  // Firestore 'nurse_qualifications' (live)
  String? _selectedNurseQualification;
  List<String> _nurseQualifications = [];

  // Therapist Fields Controllers
  final TextEditingController _therapistNameController = TextEditingController();
  final TextEditingController _therapistLastNameController = TextEditingController();
  final TextEditingController _therapistPhoneController = TextEditingController();
  final TextEditingController _therapistOrgController = TextEditingController();
  final TextEditingController _therapistExpController = TextEditingController();
  final TextEditingController _therapistCityController = TextEditingController();

  // Care physician fields (procedures, duty types, areas: profile wizard)
  final TextEditingController _cpFirstController = TextEditingController();
  final TextEditingController _cpLastController = TextEditingController();
  final TextEditingController _cpPhoneController = TextEditingController();
  final TextEditingController _cpRegNoController = TextEditingController();
  final TextEditingController _cpExpController = TextEditingController();
  String? _cpQualification;
  // "I work with a care physician agency": joins it straight away
  bool _cpWithAgency = false;
  Map<String, dynamic>? _cpAgency;
  late final Stream<List<Map<String, dynamic>>> _cpAgencies =
      CarePhysicianService.careAgenciesStream();
  // "I work with a nurse agency": joins it straight away
  bool _nurseWithAgency = false;
  Map<String, dynamic>? _nurseAgency;
  late final Stream<List<Map<String, dynamic>>> _nurseAgencies =
      NurseStaffingService.careAgenciesStream();
  // "I work with a technician partner": joins it straight away
  bool _techWithAgency = false;
  Map<String, dynamic>? _techAgency;
  late final Stream<List<Map<String, dynamic>>> _techAgencies =
      TechnicianStaffingService.careAgenciesStream();
  // Loaded from Firestore 'therapist_qualifications' (no hardcoded values)
  String? _selectedTherapistQualification;
  List<String> _therapistQualifications = [];

  static String _fullName(
          TextEditingController first, TextEditingController last) =>
      '${first.text.trim()} ${last.text.trim()}'.trim();

  /// First and last name are kept separately next to the full 'name'.
  Future<void> _saveNameParts(String collection, String uid,
      TextEditingController first, TextEditingController last) async {
    try {
      await FirestoreService.updateProviderFields(collection, uid, {
        'firstName': first.text.trim(),
        'lastName': last.text.trim(),
      });
    } catch (_) {
      // the account is created; the full name is already saved
    }
  }

  /// First name and last name side by side.
  Widget _nameFields(TextEditingController first, TextEditingController last,
      {String firstHint = '', String lastHint = ''}) {
    Widget field(String label, TextEditingController c, String hint,
            String what) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy)),
              const SizedBox(height: 6),
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: c,
                textCapitalization: TextCapitalization.words,
                validator: (v) => Validators.personName(v, label: what),
                decoration: InputDecoration(hintText: hint),
              ),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field('FIRST NAME', first, firstHint, 'first name'),
        const SizedBox(width: 12),
        field('LAST NAME', last, lastHint, 'last name'),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.initialRole;
    _listenToMasters();
  }

  /// Keeps the selected value if it is still in [list], else the first.
  static String? _keep(String? selected, List<String> list) =>
      list.contains(selected) ? selected : (list.isNotEmpty ? list.first : null);

  /// Dropdown data straight from Firestore, updated live when the admin
  /// changes it (no lists typed into the app).
  void _listenToMasters() {
    void failed(Object _) {
      if (mounted) {
        setState(() {
          _mastersFailed = true;
          _loadingCategories = false;
        });
      }
    }

    _masterSubs.addAll([
      FirestoreService.technicianQualificationsStream().listen((list) {
        if (!mounted) return;
        setState(() {
          _techQualifications = list;
          _selectedTechQualification = _keep(_selectedTechQualification, list);
        });
      }, onError: failed),
      FirestoreService.nurseQualificationsStream().listen((list) {
        if (!mounted) return;
        setState(() {
          _nurseQualifications = list;
          _selectedNurseQualification = _keep(_selectedNurseQualification, list);
        });
      }, onError: failed),
      FirestoreService.therapistQualificationsStream().listen((list) {
        if (!mounted) return;
        setState(() {
          _therapistQualifications = list;
          _selectedTherapistQualification =
              _keep(_selectedTherapistQualification, list);
        });
      }, onError: failed),
      FirestoreService.doctorCategoriesStream().listen((list) {
        if (!mounted) return;
        setState(() {
          _doctorCategories = list;
          _selectedDoctorCategory = _keep(_selectedDoctorCategory, list);
          _loadingCategories = false;
        });
      }, onError: failed),
      FirestoreService.nameMasterStream('location_master').listen((list) {
        if (!mounted) return;
        setState(() {
          _locationAreas = list;
          _selectedHospitalArea = _keep(_selectedHospitalArea, list);
        });
      }, onError: failed),
      FirestoreService.hospitalsListStream().listen((list) {
        if (!mounted) return;
        setState(() {
          _registeredHospitals = list;
          // same hospital (by id) from the new list, else the first
          final id = _selectedHospitalMap?['uid'];
          _selectedHospitalMap = list.firstWhere(
            (h) => h['uid'] == id,
            orElse: () => list.isNotEmpty ? list.first : <String, dynamic>{},
          );
          if (_selectedHospitalMap!.isEmpty) _selectedHospitalMap = null;
        });
      }, onError: failed),
    ]);
  }

  /// Shown under a dropdown that has nothing to pick from.
  Widget _noOptions(List<dynamic> list, String what) => list.isEmpty
      ? Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _mastersFailed
                ? 'Could not load $what. Check your internet connection.'
                : 'No $what available yet. Please contact MyDox support.',
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        )
      : const SizedBox.shrink();

  @override
  void dispose() {
    for (final sub in _masterSubs) {
      sub.cancel();
    }
    _hospitalNameController.dispose();
    _hospitalPhoneController.dispose();
    _hospitalAddressController.dispose();
    _ambDriverController.dispose();
    _ambDriverLastController.dispose();
    _ambVehicleController.dispose();
    _ambCityController.dispose();
    _ambPhoneController.dispose();
    _doctorNameController.dispose();
    _doctorLastNameController.dispose();
    _doctorMobileController.dispose();
    _patientNameController.dispose();
    _patientLastNameController.dispose();
    _patientPhoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _patientAgeController.dispose();
    _techNameController.dispose();
    _techLastNameController.dispose();
    _techPhoneController.dispose();
    _techOrgController.dispose();
    _techExpController.dispose();
    _techCityController.dispose();
    _nurseNameController.dispose();
    _nurseLastNameController.dispose();
    _nursePhoneController.dispose();
    _nurseOrgController.dispose();
    _nurseExpController.dispose();
    _nurseCityController.dispose();
    _therapistNameController.dispose();
    _therapistLastNameController.dispose();
    _therapistPhoneController.dispose();
    _therapistOrgController.dispose();
    _therapistExpController.dispose();
    _therapistCityController.dispose();
    for (final c in [
      _cpFirstController,
      _cpLastController,
      _cpPhoneController,
      _cpRegNoController,
      _cpExpController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!FormUtils.validate(_formKey)) return;

    if (_selectedRole == 'doctor' &&
        (_selectedDoctorCategory == null || _selectedDoctorCategory!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a doctor category'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_selectedRole == 'hospital' && _hospitalPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please capture the hospital\'s live location first. It is required and cannot be changed later.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_selectedRole == 'technician' && _techWithAgency && _techAgency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your partner'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_selectedRole == 'nurse' && _nurseWithAgency && _nurseAgency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your agency'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (_selectedRole == 'care_physician' && _cpWithAgency && _cpAgency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your agency'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (_selectedRole == 'care_physician' && _cpQualification == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your qualification'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // Verify the mobile number with an OTP before creating the profile
    final String phone = switch (_selectedRole) {
      'hospital' => _hospitalPhoneController.text,
      'ambulance' => _ambPhoneController.text,
      'doctor' => _doctorMobileController.text,
      'technician' => _techPhoneController.text,
      'nurse' => _nursePhoneController.text,
      'therapist' => _therapistPhoneController.text,
      'care_physician' => _cpPhoneController.text,
      _ => _patientPhoneController.text,
    };

    final phoneError = Validators.mobile(phone);
    if (phoneError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(phoneError), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _isLoading = true);

    var accountCreated = false;
    try {
      // the login (email + password); the profile below is saved for it
      await _authService.createAccount(
          _emailController.text, _passwordController.text);
      accountCreated = true;
      // one mobile number, one account (the email is unique already)
      if (await _authService.isPhoneTaken(phone)) {
        throw Exception(
            'This mobile number is already registered with another account. '
            'Please log in to that account, or use a different mobile number.');
      }

      if (_selectedRole == 'hospital') {
        final String area = _selectedHospitalArea ?? '';
        final String exactAddress = _hospitalAddressController.text.trim();

        // Fixed location captured on this screen (used for the 4 km radius)
        final double lat = _hospitalPos!.latitude;
        final double lng = _hospitalPos!.longitude;

        final hospitalUser = await _authService.registerHospital(
          hospitalName: _hospitalNameController.text.trim(),
          city: area,
          phone: _hospitalPhoneController.text.trim(),
        );

        final uid = hospitalUser.uid;
        final hMap = hospitalUser.toMap();
        hMap['exactAddress'] = exactAddress;
        hMap['preferredLocations'] = [area];
        hMap['homeAddress'] = exactAddress;
        hMap['latitude'] = lat;
        hMap['longitude'] = lng;
        hMap['locationLocked'] = true; // fixed: cannot be changed later
        hMap['locationCapturedAt'] = IstClock.now().toIso8601String();
        if (_hospitalPlace.isNotEmpty) hMap['locationName'] = _hospitalPlace;

        await AppDatabase.instance
            .collection('hospitals')
            .doc(uid)
            .set(hMap, SetOptions(merge: true));
        await FirestoreService.saveAccountRecord(hMap, uid);

        if (!mounted) return;
        final hospitalName = _hospitalNameController.text.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hospitalName.isEmpty
                ? 'Hospital registered successfully. Please upload the necessary documents.'
                : '$hospitalName registered successfully. Please upload the necessary documents.'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                HospitalHomeScreen(hospital: UserModel.fromMap(hMap, uid)),
          ),
          (route) => false,
        );
      } else if (_selectedRole == 'ambulance') {
        double? ambLat;
        double? ambLng;
        String ambCity = 'Pune';
        try {
          final pos = await LabLocation.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 8),
            ),
          );
          ambLat = pos.latitude;
          ambLng = pos.longitude;
          ambCity = await LocationService.getCurrentLocation();
        } catch (_) {}

        final ambUser = await _authService.registerAmbulance(
          driverName: _fullName(_ambDriverController, _ambDriverLastController),
          vehicleNumber: _ambVehicleController.text,
          city: ambCity,
          phone: _ambPhoneController.text,
        );
        await _saveNameParts('ambulances', ambUser.uid, _ambDriverController, _ambDriverLastController);

        // Save the ambulance's live GPS position (not a typed area)
        if (ambLat != null && ambLng != null) {
          final locData = {'latitude': ambLat, 'longitude': ambLng, 'city': ambCity};
          final db = AppDatabase.instance;
          await db.collection('ambulances').doc(ambUser.uid).set(locData, SetOptions(merge: true));
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ambulance Account Created Successfully!'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AmbulanceHomeScreen(ambulance: ambUser),
          ),
          (route) => false,
        );
      } else if (_selectedRole == 'doctor') {
        final String selectedHospitalName = _selectedHospitalMap?['name'] ??
            _selectedHospitalMap?['hospital'] ??
            'Ruby Hospital';
        final String hospitalArea = (_selectedHospitalMap?['preferredLocations']
                    as List<dynamic>?)
                ?.first
                ?.toString() ??
            _selectedHospitalMap?['city'] ??
            'Wakad';
        final String hospitalAddress = _selectedHospitalMap?['homeAddress'] ??
            _selectedHospitalMap?['exactAddress'] ??
            selectedHospitalName;

        final doctorUser = await _authService.registerDoctor(
          name: _fullName(_doctorNameController, _doctorLastNameController),
          category: _selectedDoctorCategory!,
          hospital: selectedHospitalName,
          mobileNumber: _doctorMobileController.text,
          hospitalArea: hospitalArea,
          hospitalAddress: hospitalAddress,
        );
        await _saveNameParts('doctors', doctorUser.uid, _doctorNameController, _doctorLastNameController);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doctor Account Created Successfully!'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => DoctorHomeScreen(doctor: doctorUser),
          ),
          (route) => false,
        );
      } else if (_selectedRole == 'technician') {
        final techUser = await _authService.registerTechnician(
          name: _fullName(_techNameController, _techLastNameController),
          phone: _techPhoneController.text,
          qualification: _selectedTechQualification ?? '',
          organisation: _techOrgController.text.isNotEmpty
              ? _techOrgController.text
              : 'MyDox Diagnostics',
          experience: _techExpController.text,
          city: _techCityController.text,
        );
        await _saveNameParts('technicians', techUser.uid, _techNameController, _techLastNameController);
        if (_techWithAgency && _techAgency != null) {
          try {
            await TechnicianStaffingService.joinAgency({
              'uid': techUser.uid,
              'name': techUser.name,
              'phone': _techPhoneController.text.trim(),
              'qualification': _selectedTechQualification ?? '',
            }, _techAgency!['id'].toString(),
                (_techAgency!['name'] ?? '').toString());
          } catch (_) {
            // the account is created; they can join from Hospital duties
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Technician Account Created Successfully!'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => TechnicianStaffingScreen(user: techUser),
          ),
          (route) => false,
        );
      } else if (_selectedRole == 'nurse') {
        final nurseUser = await _authService.registerNurse(
          name: _fullName(_nurseNameController, _nurseLastNameController),
          phone: _nursePhoneController.text,
          qualification: _selectedNurseQualification ?? '',
          organisation: _nurseOrgController.text.isNotEmpty
              ? _nurseOrgController.text
              : 'City Home Care Nursing',
          experience: _nurseExpController.text,
          city: _nurseCityController.text,
        );
        await _saveNameParts('nurses', nurseUser.uid, _nurseNameController, _nurseLastNameController);
        if (_nurseWithAgency && _nurseAgency != null) {
          try {
            await NurseStaffingService.joinAgency({
              'uid': nurseUser.uid,
              'name': nurseUser.name,
              'phone': _nursePhoneController.text.trim(),
              'qualification': _selectedNurseQualification ?? '',
            }, _nurseAgency!['id'].toString(),
                (_nurseAgency!['name'] ?? '').toString());
          } catch (_) {
            // the account is created; they can join from Hospital duties
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nurse Account Created Successfully!'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => NurseStaffingScreen(user: nurseUser),
          ),
          (route) => false,
        );
      } else if (_selectedRole == 'care_physician') {
        final cpUser = await _authService.registerCarePhysician(
          firstName: _cpFirstController.text,
          lastName: _cpLastController.text,
          phone: _cpPhoneController.text,
          qualification: _cpQualification!,
          regNo: _cpRegNoController.text,
          experienceYears:
              int.tryParse(_cpExpController.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        );
        if (_cpWithAgency && _cpAgency != null) {
          try {
            await CarePhysicianService.joinAgency({
              'uid': cpUser.uid,
              'name': cpUser.name,
              'phone': _cpPhoneController.text.trim(),
              'qualification': _cpQualification,
              'regNo': _cpRegNoController.text.trim(),
            }, _cpAgency!['id'].toString(), (_cpAgency!['name'] ?? '').toString());
          } catch (_) {
            // the account is created; they can join from their profile
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Care Physician account created! Complete your profile to see shifts that fit you.'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => CarePhysicianHomeScreen(user: cpUser),
          ),
          (route) => false,
        );
      } else if (_selectedRole == 'therapist') {
        final therapistUser = await _authService.registerTherapist(
          name: _fullName(_therapistNameController, _therapistLastNameController),
          phone: _therapistPhoneController.text.trim(),
          qualification: _selectedTherapistQualification ?? '',
          organisation: _therapistOrgController.text.isNotEmpty
              ? _therapistOrgController.text
              : 'Independent Care',
          experience: _therapistExpController.text,
          city: _therapistCityController.text,
          degreeCertUrl: '',
        );
        await _saveNameParts('therapists', therapistUser.uid, _therapistNameController, _therapistLastNameController);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Therapist Account Created! Please complete profile from Dashboard.'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => TherapistHomeScreen(therapist: therapistUser),
          ),
          (route) => false,
        );
      } else {
        final patientUser = await _authService.registerPatient(
          name: _fullName(_patientNameController, _patientLastNameController),
          phone: _patientPhoneController.text,
          age: _patientAgeController.text,
        );
        await _saveNameParts('patients', patientUser.uid, _patientNameController, _patientLastNameController);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient Account Created Successfully!'),
            backgroundColor: AppColors.successDark,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => PatientHomeScreen(patient: patientUser),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      // the profile could not be saved: remove the new login so the same
      // email can be used again
      if (accountCreated) await _authService.discardNewAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.of(e, action: 'create your account')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildRoleChip(String role, String label, IconData icon) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () {
        if (_selectedRole != role) {
          setState(() {
            _selectedRole = role;
            _formKey.currentState?.reset();
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppColors.slate,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.slate,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Form(
          key: _formKey,
          // The whole form is checked on Register; while typing, each field
          // checks only itself (see autovalidateMode on the fields)
          autovalidateMode: AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'I want to register as:',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 10),

              // Role Selector Bar
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildRoleChip(
                          'patient', 'Patient', Icons.person_rounded),
                      _buildRoleChip(
                          'hospital', 'Hospital', Icons.local_hospital_rounded),
                      _buildRoleChip('doctor', 'Doctor',
                          Icons.medical_services_rounded),
                      _buildRoleChip('ambulance', 'Ambulance',
                          Icons.airport_shuttle_rounded),
                      _buildRoleChip(
                          'technician', AppStrings.roleName('technician'),
                          Icons.science_rounded),
                      _buildRoleChip(
                          'therapist', 'Therapist', Icons.self_improvement_rounded),
                      _buildRoleChip(
                          'nurse', 'Nurse', Icons.local_hospital_rounded),
                      _buildRoleChip('care_physician', 'Care Physician',
                          Icons.medical_information_outlined),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Dynamic Fields based on Role
              if (_selectedRole == 'hospital') ...[
                // --- HOSPITAL FIELDS ---
                const Text(
                  'Hospital Registration Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Hospital Name',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _hospitalNameController,
                  validator: (v) => Validators.orgName(v, label: 'hospital name'),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Ruby Hall Clinic / City Care Hospital',
                    prefixIcon: Icon(Icons.local_hospital_outlined,
                        color: AppColors.brand),
                  ),
                ),

                const SizedBox(height: 16),

                const Text('Hospital Area',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                // filled from the live location below; else searched
                FormField<String>(
                  key: ValueKey(_selectedHospitalArea),
                  initialValue: _selectedHospitalArea,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (_) => (_selectedHospitalArea ?? '').isEmpty
                      ? 'Select the hospital area'
                      : null,
                  builder: (field) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _locationAreas.isEmpty
                        ? null
                        : () => _pickHospitalArea(field),
                    child: InputDecorator(
                      isEmpty: (_selectedHospitalArea ?? '').isEmpty,
                      decoration: InputDecoration(
                        hintText: 'Search and select area',
                        errorText: field.errorText,
                        prefixIcon: const Icon(Icons.place_outlined,
                            color: AppColors.brand),
                        suffixIcon: const Icon(Icons.search_rounded),
                      ),
                      child: Text(_selectedHospitalArea ?? ''),
                    ),
                  ),
                ),
                if (_areaNotDetected)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'We could not find your area from the live location. Please search and select it.',
                      style: TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                  ),
                _noOptions(_locationAreas, 'areas'),

                const SizedBox(height: 16),

                const Text('Exact Hospital Address / Street Address',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _hospitalAddressController,
                  validator: (v) => Validators.address(v, label: 'hospital address'),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Plot 12, Main Road, Near Dutta Mandir, Wakad',
                    prefixIcon: Icon(Icons.home_outlined,
                        color: AppColors.brand),
                  ),
                ),

                const SizedBox(height: 16),

                // Fixed live location (captured once)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _hospitalPos != null
                        ? AppColors.successTint
                        : AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _hospitalPos != null
                            ? AppColors.successLight
                            : AppColors.danger.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hospital Live Location (required)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text(
                        'Capture this while you are at the hospital. This becomes the hospital\'s fixed location, used to match patients within 4 / 6 / 8 km. It cannot be changed after registration.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 10),
                      if (_hospitalPos != null) ...[
                        Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 18, color: AppColors.successDark),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _hospitalPlace.isNotEmpty
                                    ? 'Location captured: $_hospitalPlace'
                                    : 'Location captured',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.successDeep),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_locationError != null) ...[
                        Text(_locationError!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.danger)),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton.icon(
                        onPressed:
                            _capturingLocation ? null : _captureHospitalLocation,
                        icon: _capturingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(_hospitalPos == null
                            ? 'Capture live location'
                            : 'Re-capture before registering'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                const Text('Emergency Phone',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _hospitalPhoneController,
                  validator: (v) => Validators.contactNumber(v),
                  inputFormatters: Validators.phoneInput,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '+91 20 2616 3391',
                    prefixIcon:
                        Icon(Icons.phone_outlined, color: AppColors.brand),
                  ),
                ),
              ] else if (_selectedRole == 'ambulance') ...[
                // --- AMBULANCE FIELDS ---
                const Text(
                  'Ambulance Service Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 16),

                _nameFields(_ambDriverController, _ambDriverLastController,
                    firstHint: 'e.g. Ramesh', lastHint: 'e.g. Patil'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('VEHICLE NUMBER',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _ambVehicleController,
                            validator: Validators.vehicleNumber,
                            decoration: const InputDecoration(
                              hintText: 'e.g. MH12AB1234',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PHONE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _ambPhoneController,
                            validator: Validators.mobile,
                            inputFormatters: Validators.phoneInput,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              hintText: '+91 98765 43210',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else if (_selectedRole == 'nurse') ...[
                // --- NURSE FIELDS ---
                const Text(
                  'Nurse Profile Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 16),

                _nameFields(_nurseNameController, _nurseLastNameController,
                    firstHint: 'e.g. Priya', lastHint: 'e.g. Sharma'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PHONE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _nursePhoneController,
                            validator: Validators.mobile,
                            inputFormatters: Validators.phoneInput,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              hintText: '+91 98765 43210',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('QUALIFICATION',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            // long lists scroll instead of covering the form
                            menuMaxHeight: 320,
                            value: _selectedNurseQualification,
                            isExpanded: true,
                            hint: const Text('Select qualification'),
                            validator: (val) => val == null || val.isEmpty
                                ? 'Select your qualification'
                                : null,
                            decoration: const InputDecoration(),
                            items: _nurseQualifications.map((q) {
                              return DropdownMenuItem<String>(
                                value: q,
                                child: Text(q,
                                    style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedNurseQualification = val);
                              }
                            },
                          ),
                          _noOptions(_nurseQualifications, 'qualifications'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ORGANISATION / HOSPITAL',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _nurseOrgController,
                            validator: (v) => Validators.orgName(v, optional: true),
                            decoration: const InputDecoration(
                              hintText: 'City Care Nursing',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('YEARS OF EXPERIENCE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _nurseExpController,
                            validator: Validators.experience,
                            inputFormatters: Validators.digitsInput(2),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 5',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CITY',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _nurseCityController,
                            validator: Validators.city,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Pune',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _nurseWithAgency,
                  title: const Text('I work with a nurse agency',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Your agency can place you in hospitals. Leave it unticked to work as a freelancer.',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() {
                    _nurseWithAgency = v ?? false;
                    if (!_nurseWithAgency) _nurseAgency = null;
                  }),
                ),
                if (_nurseWithAgency)
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _nurseAgencies,
                    builder: (context, snap) {
                      final agencies = snap.data ?? const [];
                      if (snap.hasData && agencies.isEmpty) {
                        return const Text('No nurse agencies are listed yet.',
                            style: TextStyle(color: AppTheme.textMuted));
                      }
                      return DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        menuMaxHeight: 320,
                        value: _nurseAgency?['id']?.toString(),
                        isExpanded: true,
                        hint: Text(snap.hasData
                            ? 'Select your agency'
                            : 'Loading agencies…'),
                        items: [
                          for (final a in agencies)
                            DropdownMenuItem(
                                value: a['id'].toString(),
                                child: Text((a['name'] ?? '').toString())),
                        ],
                        onChanged: (id) => setState(() => _nurseAgency =
                            agencies.firstWhere((a) => a['id'] == id)),
                      );
                    },
                  ),
              ] else if (_selectedRole == 'care_physician') ...[
                // --- CARE PHYSICIAN FIELDS ---
                const Text(
                  'Care Physician Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Claim per-shift hospital duties and apply for full-time RMO jobs.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 16),
                _nameFields(_cpFirstController, _cpLastController,
                    firstHint: 'e.g. Nikhil', lastHint: 'e.g. Bhosale'),
                const SizedBox(height: 16),
                const Text('MOBILE NUMBER',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _cpPhoneController,
                  validator: Validators.mobile,
                  inputFormatters: Validators.phoneInput,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '+91 98765 43210',
                    prefixIcon: Icon(Icons.phone_android_outlined,
                        color: AppColors.brand),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('QUALIFICATION',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  // long lists scroll instead of covering the form
                  menuMaxHeight: 320,
                  value: _cpQualification,
                  isExpanded: true,
                  hint: const Text('Select qualification'),
                  items: [
                    for (final e in CarePhysicianService.qualifications.entries)
                      DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.value.$1} · ${e.value.$2}')),
                  ],
                  onChanged: (v) => setState(() => _cpQualification = v),
                ),
                const SizedBox(height: 16),
                const Text('MEDICAL REGISTRATION NUMBER',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _cpRegNoController,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Please enter your registration number'
                      : Validators.registrationNumber(v),
                  decoration: const InputDecoration(
                    hintText: 'e.g. MMC-2019-08421',
                    prefixIcon:
                        Icon(Icons.badge_outlined, color: AppColors.brand),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Verified against the council register before you can claim ICU or procedure duties.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 16),
                const Text('YEARS OF EXPERIENCE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _cpExpController,
                  validator: Validators.experience,
                  keyboardType: TextInputType.number,
                  inputFormatters: Validators.digitsInput(2),
                  decoration: const InputDecoration(
                    hintText: 'e.g. 4',
                    prefixIcon: Icon(Icons.work_history_outlined,
                        color: AppColors.brand),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _cpWithAgency,
                  title: const Text('I work with a care physician agency',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      "You'll get your agency's patients' home visits first. Leave it unticked to work as a freelancer.",
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() {
                    _cpWithAgency = v ?? false;
                    if (!_cpWithAgency) _cpAgency = null;
                  }),
                ),
                if (_cpWithAgency)
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _cpAgencies,
                    builder: (context, snap) {
                      final agencies = snap.data ?? const [];
                      if (snap.hasData && agencies.isEmpty) {
                        return const Text(
                            'No care physician agencies are listed yet.',
                            style: TextStyle(color: AppTheme.textMuted));
                      }
                      return DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        // long lists scroll instead of covering the form
                        menuMaxHeight: 320,
                        value: _cpAgency?['id']?.toString(),
                        isExpanded: true,
                        hint: Text(snap.hasData
                            ? 'Select your agency'
                            : 'Loading agencies…'),
                        items: [
                          for (final a in agencies)
                            DropdownMenuItem(
                                value: a['id'].toString(),
                                child: Text((a['name'] ?? '').toString())),
                        ],
                        onChanged: (id) => setState(() => _cpAgency =
                            agencies.firstWhere((a) => a['id'] == id)),
                      );
                    },
                  ),
              ] else if (_selectedRole == 'therapist') ...[
                // --- THERAPIST FIELDS ---
                const Text(
                  'Therapist Profile Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 16),

                _nameFields(_therapistNameController, _therapistLastNameController,
                    firstHint: 'e.g. Anita', lastHint: 'e.g. Roy'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PHONE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _therapistPhoneController,
                            validator: Validators.mobile,
                            inputFormatters: Validators.phoneInput,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              hintText: '+91 98765 43210',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('QUALIFICATION',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            // long lists scroll instead of covering the form
                            menuMaxHeight: 320,
                            value: _selectedTherapistQualification,
                            isExpanded: true,
                            hint: const Text('Select qualification'),
                            validator: (val) => val == null || val.isEmpty
                                ? 'Select your qualification'
                                : null,
                            decoration: const InputDecoration(),
                            items: _therapistQualifications.map((q) {
                              return DropdownMenuItem<String>(
                                value: q,
                                child: Text(q,
                                    style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedTherapistQualification = val);
                              }
                            },
                          ),
                          _noOptions(_therapistQualifications, 'qualifications'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ORGANISATION',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _therapistOrgController,
                            validator: (v) => Validators.orgName(v, optional: true),
                            decoration: const InputDecoration(
                              hintText: 'e.g. MyDox Care',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('YEARS OF EXPERIENCE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _therapistExpController,
                            validator: Validators.experience,
                            inputFormatters: Validators.digitsInput(2),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 5',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CITY',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _therapistCityController,
                            validator: Validators.city,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Pune',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else if (_selectedRole == 'technician') ...[
                // --- TECHNICIAN FIELDS ---
                const Text(
                  'Technician Profile Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 16),

                _nameFields(_techNameController, _techLastNameController,
                    firstHint: 'e.g. Rohit', lastHint: 'e.g. Kale'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PHONE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _techPhoneController,
                            validator: Validators.mobile,
                            inputFormatters: Validators.phoneInput,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              hintText: '+91 98765 43210',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('QUALIFICATION',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            // long lists scroll instead of covering the form
                            menuMaxHeight: 320,
                            value: _selectedTechQualification,
                            isExpanded: true,
                            hint: const Text('Select qualification'),
                            validator: (val) => val == null || val.isEmpty
                                ? 'Select your qualification'
                                : null,
                            decoration: const InputDecoration(),
                            items: _techQualifications.map((q) {
                              return DropdownMenuItem<String>(
                                value: q,
                                child: Text(q,
                                    style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedTechQualification = val);
                              }
                            },
                          ),
                          _noOptions(_techQualifications, 'qualifications'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ORGANISATION / LAB (OPTIONAL)',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _techOrgController,
                            validator: (v) => Validators.orgName(v, optional: true),
                            decoration: const InputDecoration(
                              hintText: 'MyDox Diagnostics',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('YEARS OF EXPERIENCE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _techExpController,
                            validator: Validators.experience,
                            inputFormatters: Validators.digitsInput(2),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 6',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CITY',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextFormField(
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            controller: _techCityController,
                            validator: Validators.city,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Pune',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _techWithAgency,
                  title: const Text('I work with a technician partner',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Your partner can place you in hospitals. Leave it unticked to work as a freelancer.',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() {
                    _techWithAgency = v ?? false;
                    if (!_techWithAgency) _techAgency = null;
                  }),
                ),
                if (_techWithAgency)
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _techAgencies,
                    builder: (context, snap) {
                      final agencies = snap.data ?? const [];
                      if (snap.hasData && agencies.isEmpty) {
                        return const Text('No technician partners are listed yet.',
                            style: TextStyle(color: AppTheme.textMuted));
                      }
                      return DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        menuMaxHeight: 320,
                        value: _techAgency?['id']?.toString(),
                        isExpanded: true,
                        hint: Text(snap.hasData
                            ? 'Select your partner'
                            : 'Loading partners…'),
                        items: [
                          for (final a in agencies)
                            DropdownMenuItem(
                                value: a['id'].toString(),
                                child: Text((a['name'] ?? '').toString())),
                        ],
                        onChanged: (id) => setState(() => _techAgency =
                            agencies.firstWhere((a) => a['id'] == id)),
                      );
                    },
                  ),
              ] else if (_selectedRole == 'doctor') ...[
                // --- DOCTOR FIELDS ---
                const Text(
                  'Doctor Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 16),

                _nameFields(_doctorNameController, _doctorLastNameController,
                    firstHint: 'e.g. Elizabeth', lastHint: 'e.g. Amelia'),

                const SizedBox(height: 16),

                const Text('Doctor Category',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _loadingCategories
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.lineStrong),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brand,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Loading categories...'),
                          ],
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        // long lists scroll instead of covering the form
                        menuMaxHeight: 320,
                        value: _selectedDoctorCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.category_outlined,
                              color: AppColors.brand),
                        ),
                        items: _doctorCategories.map((category) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Text(category),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedDoctorCategory = value;
                          });
                        },
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Please select a category';
                          }
                          return null;
                        },
                      ),
                if (!_loadingCategories) _noOptions(_doctorCategories, 'doctor categories'),

                const SizedBox(height: 16),

                // HOSPITAL SELECTION DROPDOWN (Fetched from Firestore 'hospitals')
                const Text('Associated Hospital',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<Map<String, dynamic>>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  // long lists scroll instead of covering the form
                  menuMaxHeight: 320,
                  value: _selectedHospitalMap,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.local_hospital_outlined,
                        color: AppColors.brand),
                  ),
                  // long hospital names wrap (up to 2 lines) instead of being cut
                  itemHeight: null,
                  selectedItemBuilder: (context) => [
                    for (final hMap in _registeredHospitals)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          (hMap['name'] ?? hMap['hospital'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  items: _registeredHospitals.map((hMap) {
                    final hName = hMap['name'] ?? hMap['hospital'] ?? '';
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: hMap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(hName.toString()),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedHospitalMap = value;
                    });
                  },
                  validator: (val) {
                    if (val == null) {
                      return 'Please select associated hospital';
                    }
                    return null;
                  },
                ),
                _noOptions(_registeredHospitals, 'hospitals'),

                if (_selectedHospitalMap != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // the full name, however long
                        Text(
                          (_selectedHospitalMap!['name'] ??
                                  _selectedHospitalMap!['hospital'] ??
                                  '')
                              .toString(),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkNavy),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Address: ${_selectedHospitalMap!['homeAddress'] ?? _selectedHospitalMap!['exactAddress'] ?? 'Main Street Address'}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                const Text('Doctor Mobile Number',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _doctorMobileController,
                  validator: Validators.mobile,
                  inputFormatters: Validators.phoneInput,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '+91 98765 43210',
                    prefixIcon: Icon(Icons.phone_android_outlined,
                        color: AppColors.brand),
                  ),
                ),
              ] else ...[
                // --- PATIENT FIELDS ---
                const Text(
                  'Patient Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 16),

                _nameFields(_patientNameController, _patientLastNameController,
                    firstHint: 'e.g. Fateha', lastHint: 'e.g. Nil'),

                const SizedBox(height: 16),

                const Text('Phone Number',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _patientPhoneController,
                  validator: Validators.mobile,
                  inputFormatters: Validators.phoneInput,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '+91 98765 43210',
                    prefixIcon:
                        Icon(Icons.phone_outlined, color: AppColors.brand),
                  ),
                ),

                const SizedBox(height: 16),

                const Text('Patient Age',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _patientAgeController,
                  validator: Validators.age,
                  inputFormatters: Validators.digitsInput(3),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'e.g. 28',
                    prefixIcon: Icon(Icons.cake_outlined,
                        color: AppColors.brand),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              const Divider(height: 30),

              // --- LOGIN DETAILS: email + password ---
              const Text('Your login',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark)),
              const SizedBox(height: 4),
              const Text(
                  'You will log in with this email and password. Your mobile number above is saved on your profile.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                validator: Validators.email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.newUsername],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'name@example.com',
                  prefixIcon:
                      Icon(Icons.email_outlined, color: AppColors.brand),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                validator: Validators.newPassword,
                // the rule is shown as soon as it is not met
                autovalidateMode: AutovalidateMode.onUserInteraction,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Create password',
                  helperText: 'At least 8 characters, with a letter and a number',
                  prefixIcon: const Icon(Icons.lock_outline_rounded,
                      color: AppColors.brand),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(_showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmPasswordController,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => (v ?? '').isEmpty
                    ? 'Please confirm your password'
                    : v != _passwordController.text
                        ? 'The passwords do not match'
                        : null,
                obscureText: !_showConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_reset_rounded,
                      color: AppColors.brand),
                  suffixIcon: IconButton(
                    tooltip: _showConfirmPassword
                        ? 'Hide password'
                        : 'Show password',
                    icon: Icon(_showConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(
                        () => _showConfirmPassword = !_showConfirmPassword),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Register Action Button
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brand,
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _handleRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                      ),
                      child: Text(AppStrings.registerAs(_selectedRole)),
                    ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ));
  }
}

