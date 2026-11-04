import '../../services/app_database.dart';
import '../../widgets/circle_image.dart';
import '../../utils/form_utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/area_multi_select_field.dart';
import '../../widgets/verification_documents_section.dart';
import '../../utils/validators.dart';
import '../auth/login_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/profile_photo_actions.dart';

class EditTherapistProfileScreen extends StatefulWidget {
  final UserModel therapist;

  const EditTherapistProfileScreen({
    super.key,
    required this.therapist,
  });

  @override
  State<EditTherapistProfileScreen> createState() =>
      _EditTherapistProfileScreenState();
}

class _EditTherapistProfileScreenState
    extends State<EditTherapistProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _regNumberController;
  late TextEditingController _expController;
  late TextEditingController _cityController;
  late TextEditingController _summaryController;
  late TextEditingController _coursesController;
  late TextEditingController _specialInterestController;

  // All option lists below are loaded from Firestore in _loadExtendedProfile
  String? _selectedQualification;
  List<String> _qualifications = []; // 'therapist_qualifications'

  String? _profilePicUrl;
  bool _uploadingPic = false;

  // Verification Documents URLs
  String? _degreeCertUrl;
  String? _aadhaarUrl;
  String? _panUrl;
  String? _addressProofUrl;
  String? _registrationCertUrl;

  bool _isLoading = false;

  bool _loadingProfile = true;

  // Therapies Offered Chips — same catalogue patients book from ('therapies')
  Set<String> _selectedTherapies = {};
  List<String> _allTherapies = [];

  // Where you work toggles
  bool _homeVisitsEnabled = true;
  bool _clinicsEnabled = true;

  // Preferred centres/hospitals ('hospitals'), grouped by facility type.
  // Each option label is "Name · Area".
  Set<String> _selectedPreferredCenters = {};
  Map<String, List<String>> _preferredCentersByType = {};

  // Areas Covered ('location_master'); empty = take requests from any area
  Set<String> _selectedCoveredAreas = {};
  List<String> _allCoveredAreas = [];

  // Languages Spoken ('language_master')
  Set<String> _selectedLanguages = {};
  List<String> _allLanguages = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.therapist.name);
    _phoneController = TextEditingController(
        text: widget.therapist.phone ?? widget.therapist.mobileNumber ?? '');
    _regNumberController = TextEditingController();
    _expController =
        TextEditingController(text: widget.therapist.experience ?? '');
    _cityController = TextEditingController(text: widget.therapist.city ?? '');
    _summaryController = TextEditingController();
    _coursesController = TextEditingController();
    _specialInterestController = TextEditingController();

    _profilePicUrl = widget.therapist.profilePicUrl;
    _degreeCertUrl = widget.therapist.degreeCertUrl;
    _aadhaarUrl = widget.therapist.aadhaarUrl;
    _panUrl = widget.therapist.panUrl;
    _addressProofUrl = widget.therapist.addressProofUrl;
    _registrationCertUrl = widget.therapist.registrationCertUrl;

    if (widget.therapist.preferredLocations != null &&
        widget.therapist.preferredLocations!.isNotEmpty) {
      _selectedCoveredAreas = Set<String>.from(widget.therapist.preferredLocations!);
    }

    _loadExtendedProfile();
  }

  /// Add saved values missing from a master list so they stay visible
  /// (and can be deselected) even if the master entry was renamed/removed.
  static List<String> _withSaved(List<String> master, Iterable<String> saved) {
    final list = List<String>.from(master);
    for (final s in saved) {
      if (s.isNotEmpty && !list.contains(s)) list.add(s);
    }
    return list;
  }

  /// Load option lists from Firestore master collections, then the
  /// therapist-only fields that UserModel doesn't carry.
  Future<void> _loadExtendedProfile() async {
    try {
      final results = await Future.wait([
        FirestoreService.getTherapistQualificationMaster(),
        FirestoreService.getTherapiesWithPrice(),
        FirestoreService.getLocationMaster(),
        FirestoreService.getLanguageMaster(),
        FirestoreService.getCareCentres(),
      ]);
      final qualifications = results[0] as List<String>;
      final therapies = (results[1] as List<Map<String, dynamic>>)
          .map((t) => (t['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toList();
      final areas = results[2] as List<String>;
      final languages = results[3] as List<String>;
      final centres = results[4] as List<Map<String, String>>;

      final byType = <String, List<String>>{};
      for (final c in centres) {
        final label =
            c['area']!.isNotEmpty ? '${c['name']} · ${c['area']}' : c['name']!;
        byType.putIfAbsent(c['type']!.toUpperCase(), () => []).add(label);
      }

      final doc = await AppDatabase.instance
          .collection('therapists')
          .doc(widget.therapist.uid)
          .get();
      final data = doc.data();
      if (!mounted) return;

      final q = widget.therapist.qualification ?? '';
      setState(() {
        _qualifications = _withSaved(qualifications, [q]);
        _selectedQualification = q.isNotEmpty
            ? q
            : (_qualifications.isNotEmpty ? _qualifications.first : null);
        _allTherapies = therapies;
        _allCoveredAreas = _withSaved(areas, _selectedCoveredAreas);
        _allLanguages = languages;
        _preferredCentersByType = byType;
      });

      if (data != null) {
        List<String> strings(dynamic v) =>
            (v as List<dynamic>? ?? []).map((e) => e.toString()).toList();

        setState(() {
          _regNumberController.text = data['registrationNumber'] ?? '';
          _summaryController.text = data['summary'] ?? '';
          _coursesController.text = data['recentCourses'] ?? '';
          _specialInterestController.text = data['specialInterest'] ?? '';
          _homeVisitsEnabled = data['homeVisitsEnabled'] != false;
          _clinicsEnabled = data['clinicsEnabled'] != false;

          final savedTherapies = strings(data['offeredTherapies']);
          _selectedTherapies = savedTherapies.toSet();
          _allTherapies = _withSaved(_allTherapies, savedTherapies);

          final savedLanguages = strings(data['languages']);
          _selectedLanguages = savedLanguages.toSet();
          _allLanguages = _withSaved(_allLanguages, savedLanguages);

          _selectedPreferredCenters = strings(data['preferredCenters']).toSet();
          final knownCentres =
              _preferredCentersByType.values.expand((e) => e).toSet();
          final unknownCentres =
              _selectedPreferredCenters.where((c) => !knownCentres.contains(c));
          if (unknownCentres.isNotEmpty) {
            _preferredCentersByType
                .putIfAbsent('OTHER', () => [])
                .addAll(unknownCentres);
          }

          _selectedCoveredAreas = strings(data['preferredLocations']).toSet();
          _allCoveredAreas = _withSaved(_allCoveredAreas, _selectedCoveredAreas);
        });
      }
    } catch (_) {
      // Fall back to what the UserModel provided
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _regNumberController.dispose();
    _expController.dispose();
    _cityController.dispose();
    _summaryController.dispose();
    _coursesController.dispose();
    _specialInterestController.dispose();
    super.dispose();
  }

  /// Remove the photo: the default icon shows again everywhere.
  Future<void> _removeProfilePic() async {
    final old = _profilePicUrl;
    setState(() => _uploadingPic = true);
    try {
      await FirestoreService.removeProfilePic(
          uid: widget.therapist.uid, role: 'therapist', oldUrl: old);
      if (!mounted) return;
      setState(() => _profilePicUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo removed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'remove the photo')),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _uploadingPic = false);
    }
  }

  Future<void> _pickAndUploadProfilePic() async {
    final action = await askPhotoAction(context,
        hasPhoto: (_profilePicUrl ?? '').isNotEmpty);
    if (action == null || !mounted) return;
    if (action == PhotoAction.remove) return _removeProfilePic();

    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;

    setState(() => _uploadingPic = true);

    try {
      final url = await StorageService.uploadProfilePicture(
        uid: widget.therapist.uid,
        file: picked,
      );

      await FirestoreService.updateUserProfilePicUrl(
        uid: widget.therapist.uid,
        role: 'therapist',
        photoUrl: url,
      );

      if (mounted) {
        setState(() {
          _profilePicUrl = url;
          _uploadingPic = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Physio profile picture updated!'),
            backgroundColor: AppColors.successDark,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPic = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessages.of(e, action: 'upload the picture')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleSave() async {
    if (!FormUtils.validate(_formKey)) return;

    setState(() => _isLoading = true);
    try {
      final List<String> locs = _selectedCoveredAreas.toList();
      final String pic = _profilePicUrl ?? '';

      final Map<String, dynamic> updateData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'mobileNumber': _phoneController.text.trim(),
        'qualification': _selectedQualification ?? '',
        'experience': _expController.text.trim(),
        'city': _cityController.text.trim(),
        'preferredLocations': locs,
        'offeredTherapies': _selectedTherapies.toList(),
        'specialties': _selectedTherapies.toList(),
        'languages': _selectedLanguages.toList(),
        'registrationNumber': _regNumberController.text.trim(),
        'summary': _summaryController.text.trim(),
        'recentCourses': _coursesController.text.trim(),
        'specialInterest': _specialInterestController.text.trim(),
        'homeVisitsEnabled': _homeVisitsEnabled,
        'clinicsEnabled': _clinicsEnabled,
        'preferredCenters': _selectedPreferredCenters.toList(),
        if (pic.isNotEmpty) 'profilePicUrl': pic,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await FirestoreService.updateTherapistFields(
          widget.therapist.uid, updateData);

      final t = widget.therapist;
      final updatedTherapist = UserModel(
        uid: t.uid,
        email: t.email,
        role: 'therapist',
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        mobileNumber: _phoneController.text.trim(),
        qualification: _selectedQualification,
        organisation: t.organisation,
        experience: _expController.text.trim(),
        city: _cityController.text.trim(),
        profilePicUrl: _profilePicUrl,
        preferredLocations: locs,
        isVerified: t.isVerified,
        rating: t.rating,
        latitude: t.latitude,
        longitude: t.longitude,
        degreeCertUrl: _degreeCertUrl,
        aadhaarUrl: _aadhaarUrl,
        panUrl: _panUrl,
        addressProofUrl: _addressProofUrl,
        registrationCertUrl: _registrationCertUrl,
        internshipCertUrl: t.internshipCertUrl,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Physio Profile updated successfully!'),
          backgroundColor: AppColors.successDark,
        ),
      );

      Navigator.pop(context, updatedTherapist);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.of(e, action: 'update your profile')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    const primarySky = AppColors.primary;

    return ResponsiveCenter(child: Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        title: const Text('Edit Physio Profile'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.darkNavy,
        elevation: 0.5,
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator(color: primarySky))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Form(
          key: _formKey,
          // Show field errors as soon as the user edits a field
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar Upload
              Center(
                child: Stack(
                  children: [
                    SafeAvatar(
  imageUrl: _profilePicUrl,
  radius: 44,
  backgroundColor: primarySky.withValues(alpha: 0.15),
  fallback: const Icon(
                              Icons.self_improvement_rounded,
                              size: 46,
                              color: primarySky,
                            ),
),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _uploadingPic ? null : _pickAndUploadProfilePic,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: primarySky,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: _uploadingPic
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ))
                              : const Icon(Icons.camera_alt_rounded,
                                  size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // VERIFICATION DOCUMENTS (role-specific list from Firestore 'verification_requirements')
              VerificationDocumentsSection(
                role: 'therapist',
                uid: widget.therapist.uid,
                accentColor: AppTheme.primaryTeal,
              ),

              const SizedBox(height: 20),

              // BASIC FIELDS (Name, Phone, Qualification, Reg No, Exp, City)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FULL NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      validator: (v) => Validators.personName(v),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),

                    const SizedBox(height: 14),

                    const Text('PHONE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _phoneController,
                      validator: Validators.mobile,
                      inputFormatters: Validators.phoneInput,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),

                    const SizedBox(height: 14),

                    const Text('QUALIFICATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      menuMaxHeight: 320,
                      value: _selectedQualification,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      items: _qualifications.map((q) {
                        return DropdownMenuItem<String>(
                          value: q,
                          child: Text(q, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedQualification = val);
                      },
                    ),

                    const SizedBox(height: 14),

                    const Text('REGISTRATION NUMBER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _regNumberController,
                      validator: Validators.registrationNumber,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('YEARS OF EXPERIENCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _expController,
                                validator: Validators.experience,
                                inputFormatters: Validators.digitsInput(2),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                              const Text('CITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _cityController,
                                validator: Validators.city,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // THERAPIES YOU OFFER SECTION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Therapies you offer',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allTherapies.map((t) {
                        final isSelected = _selectedTherapies.contains(t);
                        return ChoiceChip(
                          label: Text(t),
                          selected: isSelected,
                          selectedColor: primarySky,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.darkNavy,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedTherapies.add(t);
                              } else {
                                _selectedTherapies.remove(t);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // WHERE YOU WORK SECTION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Where you work',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: primarySky.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Home visits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Switch(
                            value: _homeVisitsEnabled,
                            activeColor: primarySky,
                            onChanged: (val) => setState(() => _homeVisitsEnabled = val),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: primarySky.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Clinics, centres & hospitals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Switch(
                            value: _clinicsEnabled,
                            activeColor: primarySky,
                            onChanged: (val) => setState(() => _clinicsEnabled = val),
                          ),
                        ],
                      ),
                    ),

                    if (_clinicsEnabled) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Physiotherapy centres, clinics & hospitals you prefer',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                      ),
                      if (_preferredCentersByType.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'No centres or hospitals registered yet.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ),
                      for (final entry in _preferredCentersByType.entries) ...[
                        const SizedBox(height: 10),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: entry.value.map((center) {
                            final isSelected = _selectedPreferredCenters.contains(center);
                            return ChoiceChip(
                              label: Text(center),
                              selected: isSelected,
                              selectedColor: primarySky,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.darkNavy,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedPreferredCenters.add(center);
                                  } else {
                                    _selectedPreferredCenters.remove(center);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // AREAS YOU COVER & LANGUAGES SECTION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Areas you cover',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Open requests from these areas reach you. Leave empty to see requests from every area.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 10),

                    AreaMultiSelectField(
                      accent: primarySky,
                      hint: 'All areas',
                      areas: _allCoveredAreas,
                      selected: _selectedCoveredAreas,
                      onChanged: (v) =>
                          setState(() => _selectedCoveredAreas = v),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Languages',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                    ),
                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allLanguages.map((lang) {
                        final isSelected = _selectedLanguages.contains(lang);
                        return ChoiceChip(
                          label: Text(lang),
                          selected: isSelected,
                          selectedColor: primarySky,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.darkNavy,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedLanguages.add(lang);
                              } else {
                                _selectedLanguages.remove(lang);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _summaryController,
                      validator: (v) => Validators.maxLength(v, 500),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Short summary patients will see (optional)',
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // RECENT COURSES & SPECIAL INTEREST
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recent courses & special interest',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                    ),
                    const SizedBox(height: 10),

                    const Text('NEW COURSES, CERTIFICATIONS OR SPECIALITIES COMPLETED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _coursesController,
                      validator: (v) => Validators.maxLength(v, 500),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'e.g. Certified Dry Needling (2026), Advanced Manual Therapy — Pune, Vestibular rehab course',
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),

                    const SizedBox(height: 14),

                    const Text('SPECIAL INTEREST', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _specialInterestController,
                      validator: (v) => Validators.maxLength(v, 300),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'e.g. post-stroke gait training, sports shoulder, paediatric neuro',
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ACCOUNT & SIGN OUT
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Sign out of this device.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),

                    OutlinedButton(
                      onPressed: _signOut,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        side: BorderSide(color: AppColors.lineStrong),
                      ),
                      child: const Text('Log out', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // SAVE PROFILE BUTTON
              _isLoading
                  ? const Center(child: CircularProgressIndicator(color: primarySky))
                  : ElevatedButton(
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primarySky,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      ),
                      child: const Text('Save profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ));
  }
}
