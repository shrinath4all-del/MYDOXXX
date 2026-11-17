import '../../services/app_database.dart';
import '../../widgets/circle_image.dart';
import '../../widgets/delete_account_button.dart';
import '../../utils/form_utils.dart';
import '../../utils/safe_cast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/area_multi_select_field.dart';
import '../../widgets/verification_documents_section.dart';
import '../../utils/validators.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/profile_photo_actions.dart';

class EditTechnicianProfileScreen extends StatefulWidget {
  final UserModel technician;

  const EditTechnicianProfileScreen({
    super.key,
    required this.technician,
  });

  @override
  State<EditTechnicianProfileScreen> createState() =>
      _EditTechnicianProfileScreenState();
}

class _EditTechnicianProfileScreenState
    extends State<EditTechnicianProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _qualificationController;
  late TextEditingController _organisationController;
  late TextEditingController _experienceController;
  late TextEditingController _cityController;

  String? _profilePicUrl;

  // Verification Documents URLs

  bool _isLoading = false;
  bool _uploadingPic = false;

  List<Map<String, dynamic>> _availableLabTests = [];
  Set<String> _selectedOfferedTests = {};
  bool _loadingLabTests = true;

  // Areas served ('location_master'), saved as preferredLocations
  Set<String> _selectedLocations = {};
  List<String> _allLocations = [];

  @override
  void initState() {
    super.initState();
    _profilePicUrl = widget.technician.profilePicUrl;

    _nameController = TextEditingController(text: widget.technician.name);
    _phoneController = TextEditingController(
        text: widget.technician.mobileNumber ?? widget.technician.phone ?? '');
    _qualificationController = TextEditingController(
        text: widget.technician.qualification ?? '');
    _organisationController = TextEditingController(
        text: widget.technician.organisation ?? '');
    _experienceController = TextEditingController(
        text: widget.technician.experience ?? '');
    _cityController = TextEditingController(
        text: widget.technician.city ?? 'Pune');

    if (widget.technician.preferredLocations != null &&
        widget.technician.preferredLocations!.isNotEmpty) {
      _selectedLocations = Set<String>.from(widget.technician.preferredLocations!);
    }
    _allLocations = _selectedLocations.toList();

    _fetchLabTests();
  }

  /// Lab tests and areas from the masters, then the technician's saved
  /// tests and areas from their own record (UserModel doesn't carry tests).
  Future<void> _fetchLabTests() async {
    try {
      final results = await Future.wait<Object?>([
        FirestoreService.getLabTestsWithPrice(),
        FirestoreService.getLocationMaster(),
        AppDatabase.instance
            .collection('technicians')
            .doc(widget.technician.uid)
            .get(),
      ]);
      final tests = results[0] as List<Map<String, dynamic>>;
      final areas = results[1] as List<String>;
      final data =
          (results[2] as DocumentSnapshot<Map<String, dynamic>>).data() ?? {};
      List<String> strings(Object? v) => v is List
          ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : <String>[];
      if (mounted) {
        setState(() {
          _availableLabTests = tests;
          _selectedOfferedTests = strings(data['offeredTests']).toSet();
          // saved values the master no longer lists stay visible
          for (final t in _selectedOfferedTests) {
            if (!tests.any((m) => m['name'] == t)) {
              _availableLabTests = [..._availableLabTests, {'name': t}];
            }
          }
          if (data['preferredLocations'] is List) {
            _selectedLocations = strings(data['preferredLocations']).toSet();
          }
          _allLocations = [
            ...areas,
            for (final a in _selectedLocations)
              if (!areas.contains(a)) a,
          ];
          _loadingLabTests = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _availableLabTests = [];
          _loadingLabTests = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _qualificationController.dispose();
    _organisationController.dispose();
    _experienceController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  /// Remove the photo: the default icon shows again everywhere.
  Future<void> _removeProfilePic() async {
    final old = _profilePicUrl;
    setState(() => _uploadingPic = true);
    try {
      await FirestoreService.removeProfilePic(
          uid: widget.technician.uid, role: 'technician', oldUrl: old);
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
        uid: widget.technician.uid,
        file: picked,
      );

      await FirestoreService.updateUserProfilePicUrl(
        uid: widget.technician.uid,
        role: 'technician',
        photoUrl: url,
      );

      if (mounted) {
        setState(() {
          _profilePicUrl = url;
          _uploadingPic = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Technician profile picture updated!'),
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

  Future<void> _saveProfile() async {
    if (!FormUtils.validate(_formKey)) return;

    setState(() => _isLoading = true);

    try {
      final List<String> locs = _selectedLocations.toList();
      final String pic = _profilePicUrl ?? '';

      final Map<String, dynamic> techData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'mobileNumber': _phoneController.text.trim(),
        'qualification': _qualificationController.text.trim(),
        'organisation': _organisationController.text.trim(),
        'experience': _experienceController.text.trim(),
        'city': _cityController.text.trim(),
        'offeredTests': _selectedOfferedTests.toList(),
        'preferredLocations': locs,
        if (pic.isNotEmpty) 'profilePicUrl': pic,
      };

      await AppDatabase.instance
          .collection('technicians')
          .doc(widget.technician.uid)
          .set(techData, SetOptions(merge: true));

      await FirestoreService.saveAccountRecord(techData, widget.technician.uid);

      // the saved fields on top of everything else (verification, rating…)
      final updatedTechnician = UserModel.fromMap(
          {...widget.technician.toMap(), ...techData}, widget.technician.uid);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile & Preferred Locations updated!'),
          backgroundColor: AppColors.successDark,
        ),
      );

      Navigator.of(context).pop(updatedTechnician);
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

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      appBar: AppBar(
        title: const Text('Edit Technician Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded, color: AppColors.primary),
            onPressed: _isLoading ? null : _saveProfile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Form(
          key: _formKey,
          // Show field errors as soon as the user edits a field
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Center(
                child: GestureDetector(
                  onTap: _uploadingPic ? null : _pickAndUploadProfilePic,
                  child: Stack(
                    children: [
                      SafeAvatar(
  imageUrl: _profilePicUrl,
  radius: 46,
  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
  fallback: const Icon(
                                Icons.science_rounded,
                                size: 48,
                                color: AppColors.primary,
                              ),
),
                      if (_uploadingPic)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // VERIFICATION DOCUMENTS (role-specific list from Firestore 'verification_requirements')
              VerificationDocumentsSection(
                role: 'technician',
                uid: widget.technician.uid,
                accentColor: AppColors.primary,
              ),

              const SizedBox(height: 20),

              // PREFERRED SERVICE LOCATIONS CHECKBOXES SECTION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.map_rounded,
                            color: AppTheme.primaryTeal, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Preferred Service Areas / Locations',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select the areas where you offer home visit sample collection:',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),

                    AreaMultiSelectField(
                      loading: _loadingLabTests,
                      areas: _allLocations,
                      selected: _selectedLocations,
                      onChanged: (v) => setState(() => _selectedLocations = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // OFFERED LAB TESTS CHECKBOXES SECTION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.checklist_rtl_rounded,
                            color: AppColors.primary, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Offered Lab Tests & Services',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Check the lab tests you perform for home visits:',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),

                    if (_loadingLabTests)
                      const CircularProgressIndicator(color: AppColors.primary)
                    else
                      Column(
                        children: _availableLabTests.map((test) {
                          final String name = test['name'] ?? '';
                          final int price = toNum(test['price'])?.toInt() ?? 0;
                          final bool isChecked =
                              _selectedOfferedTests.contains(name);

                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            activeColor: AppColors.primary,
                            title: Text(
                              price > 0 ? '$name (₹$price)' : name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedOfferedTests.add(name);
                                } else {
                                  _selectedOfferedTests.remove(name);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Full Name & Phone
              const Text('Full Name',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) => Validators.personName(v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline_rounded,
                      color: AppColors.primary),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Phone Number',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                validator: Validators.mobile,
                inputFormatters: Validators.phoneInput,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  prefixIcon:
                      Icon(Icons.phone_outlined, color: AppColors.primary),
                ),
              ),

              const SizedBox(height: 16),

              // Qualification & Organisation
              const Text('Qualification',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _qualificationController,
                validator: (v) => Validators.qualification(v),
                decoration: const InputDecoration(
                  prefixIcon:
                      Icon(Icons.school_outlined, color: AppColors.primary),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Organisation / Lab',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _organisationController,
                validator: (v) => Validators.orgName(v, optional: true),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.business_outlined,
                      color: AppColors.primary),
                ),
              ),

              const SizedBox(height: 16),

              // Experience & City
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Years of Exp',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _experienceController,
                          validator: Validators.experience,
                          inputFormatters: Validators.digitsInput(2),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.work_history_outlined,
                                color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('City',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _cityController,
                          validator: Validators.city,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.location_city_outlined,
                                color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                      ),
                      onPressed: _saveProfile,
                      child: const Text('Save Profile & Documents'),
                    ),

              const SizedBox(height: 8),
              // remove this account for good
              const DeleteAccountButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ));
  }
}
