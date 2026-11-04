import 'dart:async';
import '../../widgets/circle_image.dart';
import '../../utils/form_utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/profile_photo_actions.dart';

class EditPatientProfileScreen extends StatefulWidget {
  final UserModel patient;

  const EditPatientProfileScreen({
    super.key,
    required this.patient,
  });

  @override
  State<EditPatientProfileScreen> createState() =>
      _EditPatientProfileScreenState();
}

class _EditPatientProfileScreenState extends State<EditPatientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _ageController;
  late TextEditingController _weightController;
  late TextEditingController _allergyController;
  late TextEditingController _homeAddressController;
  late TextEditingController _emergencyContactController;

  String? _selectedBloodGroup;
  String? _profilePicUrl;
  bool _isLoading = false;
  bool _uploadingPic = false;

  List<Map<String, dynamic>> _availableDoctors = [];
  String? _prefDoc1Uid;
  String? _prefDoc1Name;
  String? _prefDoc2Uid;
  String? _prefDoc2Name;

  final List<String> _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'O+',
    'O-',
    'AB+',
    'AB-',
  ];

  @override
  void initState() {
    super.initState();
    _profilePicUrl = widget.patient.profilePicUrl;
    _nameController = TextEditingController(text: widget.patient.name);
    _phoneController = TextEditingController(
        text: widget.patient.phone ?? widget.patient.mobileNumber ?? '');
    _ageController = TextEditingController(text: widget.patient.age ?? '');
    _weightController = TextEditingController(text: widget.patient.weight ?? '');
    _allergyController = TextEditingController(text: widget.patient.allergy ?? '');
    _homeAddressController =
        TextEditingController(text: widget.patient.homeAddress ?? '');
    _emergencyContactController =
        TextEditingController(text: widget.patient.emergencyContact ?? '');

    // never guess a blood group: unset stays unset
    if (_bloodGroups.contains(widget.patient.bloodGroup)) {
      _selectedBloodGroup = widget.patient.bloodGroup;
    }

    if (widget.patient.preferredDoctorUids != null &&
        widget.patient.preferredDoctorUids!.isNotEmpty) {
      _prefDoc1Uid = widget.patient.preferredDoctorUids![0];
      _prefDoc1Name = (widget.patient.preferredDoctorNames != null &&
              widget.patient.preferredDoctorNames!.isNotEmpty)
          ? widget.patient.preferredDoctorNames![0]
          : 'Doctor 1';

      if (widget.patient.preferredDoctorUids!.length > 1) {
        _prefDoc2Uid = widget.patient.preferredDoctorUids![1];
        _prefDoc2Name = (widget.patient.preferredDoctorNames != null &&
                widget.patient.preferredDoctorNames!.length > 1)
            ? widget.patient.preferredDoctorNames![1]
            : 'Doctor 2';
      }
    }

    _fetchDoctors();
  }

  // kept so it stops when the screen closes (it downloads every doctor)
  StreamSubscription? _doctorsSub;

  Future<void> _fetchDoctors() async {
    await _doctorsSub?.cancel();
    _doctorsSub = FirestoreService.getDoctorsStream().listen((docs) {
      if (mounted) {
        setState(() {
          _availableDoctors = docs;
        });
      }
    });
  }

  @override
  void dispose() {
    _doctorsSub?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _allergyController.dispose();
    _homeAddressController.dispose();
    _emergencyContactController.dispose();
    super.dispose();
  }

  /// Remove the photo: the default icon shows again everywhere.
  Future<void> _removeProfilePic() async {
    final old = _profilePicUrl;
    setState(() => _uploadingPic = true);
    try {
      await FirestoreService.removeProfilePic(
          uid: widget.patient.uid, role: 'patient', oldUrl: old);
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
        uid: widget.patient.uid,
        file: picked,
      );

      await FirestoreService.updateUserProfilePicUrl(
        uid: widget.patient.uid,
        role: 'patient',
        photoUrl: url,
      );

      if (mounted) {
        setState(() {
          _profilePicUrl = url;
          _uploadingPic = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
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

    final List<String> prefUids = [];
    final List<String> prefNames = [];

    if (_prefDoc1Uid != null && _prefDoc1Uid!.isNotEmpty) {
      prefUids.add(_prefDoc1Uid!);
      prefNames.add(_prefDoc1Name ?? 'Preferred Doctor 1');
    }

    if (_prefDoc2Uid != null && _prefDoc2Uid!.isNotEmpty) {
      prefUids.add(_prefDoc2Uid!);
      prefNames.add(_prefDoc2Name ?? 'Preferred Doctor 2');
    }

    try {
      final updatedUser = await _authService.updatePatientProfile(
        uid: widget.patient.uid,
        name: _nameController.text,
        phone: _phoneController.text,
        age: _ageController.text,
        bloodGroup: _selectedBloodGroup ?? '',
        weight: _weightController.text,
        allergy: _allergyController.text,
        homeAddress: _homeAddressController.text,
        emergencyContact: _emergencyContactController.text,
        profilePicUrl: _profilePicUrl,
        preferredDoctorUids: prefUids,
        preferredDoctorNames: prefNames,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile Updated Successfully'),
          backgroundColor: AppColors.successDark,
        ),
      );

      Navigator.of(context).pop(updatedUser);
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
        title: const Text('Edit Patient Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded, color: AppTheme.primaryTeal),
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
              // Avatar Header
              Center(
                child: GestureDetector(
                  onTap: _uploadingPic ? null : _pickAndUploadProfilePic,
                  child: Stack(
                    children: [
                      SafeAvatar(
  imageUrl: _profilePicUrl,
  radius: 46,
  backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
  fallback: const Icon(
                                Icons.person_rounded,
                                size: 52,
                                color: AppTheme.primaryTeal,
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
                            color: AppTheme.primaryTeal,
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

              // 1. Patient Name
              const Text('Full Name',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) => Validators.personName(v, label: 'patient name'),
                decoration: const InputDecoration(
                  hintText: 'Enter patient full name',
                  prefixIcon: Icon(Icons.person_outline_rounded,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // 2. Phone Number
              const Text('Phone Number',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                validator: Validators.mobile,
                inputFormatters: Validators.phoneInput,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: '+91 98765 43210',
                  prefixIcon: Icon(Icons.phone_outlined,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // Age & Blood Group Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Age',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _ageController,
                          validator: Validators.age,
                          inputFormatters: Validators.digitsInput(3),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'e.g. 28',
                            prefixIcon: Icon(Icons.cake_outlined,
                                color: AppTheme.primaryTeal),
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
                        const Text('Blood Group',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          menuMaxHeight: 320,
                          isExpanded: true,
                          value: _selectedBloodGroup,
                          hint: const Text('Select'),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.bloodtype_outlined,
                                color: AppTheme.primaryTeal),
                          ),
                          items: _bloodGroups.map((bg) {
                            return DropdownMenuItem<String>(
                              value: bg,
                              child: Text(bg),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedBloodGroup = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // PREFERRED DOCTORS SECTION (Pick up to 2)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.star_rounded, color: AppColors.warningBright, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Preferred Doctors (Up to 2)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Emergency & Home requests will target your 1st preferred doctor directly before broadcasting.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),

                    // Preferred Doctor 1 Dropdown
                    const Text('1st Preferred Doctor (Primary)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      menuMaxHeight: 320,
                      isExpanded: true,
                      value: _availableDoctors.any((d) => d['uid'] == _prefDoc1Uid) ? _prefDoc1Uid : null,
                      decoration: const InputDecoration(
                        hintText: 'Select 1st Preferred Doctor',
                        prefixIcon: Icon(Icons.star_outline_rounded,
                            color: AppTheme.primaryTeal),
                      ),
                      items: _availableDoctors.map((doc) {
                        final uid = doc['uid'] ?? '';
                        final name = doc['name'] ?? 'Doctor';
                        final cat = doc['category'] ?? '';
                        return DropdownMenuItem<String>(
                          value: uid,
                          child: Text('$name ($cat)', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _prefDoc1Uid = val;
                          final match = _availableDoctors.firstWhere(
                              (d) => d['uid'] == val,
                              orElse: () => {});
                          _prefDoc1Name = match['name'] ?? 'Doctor';
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    // Preferred Doctor 2 Dropdown
                    const Text('2nd Preferred Doctor (Secondary)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      menuMaxHeight: 320,
                      isExpanded: true,
                      value: _availableDoctors.any((d) => d['uid'] == _prefDoc2Uid) ? _prefDoc2Uid : null,
                      decoration: const InputDecoration(
                        hintText: 'Select 2nd Preferred Doctor',
                        prefixIcon: Icon(Icons.star_outline_rounded,
                            color: AppTheme.primaryTeal),
                      ),
                      items: _availableDoctors.map((doc) {
                        final uid = doc['uid'] ?? '';
                        final name = doc['name'] ?? 'Doctor';
                        final cat = doc['category'] ?? '';
                        return DropdownMenuItem<String>(
                          value: uid,
                          child: Text('$name ($cat)', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _prefDoc2Uid = val;
                          final match = _availableDoctors.firstWhere(
                              (d) => d['uid'] == val,
                              orElse: () => {});
                          _prefDoc2Name = match['name'] ?? 'Doctor';
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Weight
              const Text('Weight (kg)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _weightController,
                validator: Validators.weight,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'e.g. 68 kg',
                  prefixIcon: Icon(Icons.monitor_weight_outlined,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // Allergies
              const Text('Allergies',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _allergyController,
                validator: (v) => Validators.maxLength(v, 200),
                decoration: const InputDecoration(
                  hintText: 'e.g. Penicillin, Peanuts, None',
                  prefixIcon: Icon(Icons.warning_amber_rounded,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // Home Address
              const Text('Home Address',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _homeAddressController,
                validator: (v) => Validators.address(v, label: 'home address', optional: true),
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Enter full home address',
                  prefixIcon: Icon(Icons.home_outlined,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // Emergency Contact
              const Text('Emergency Contact',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emergencyContactController,
                validator: (v) => Validators.mobile(v, label: 'emergency contact', optional: true),
                inputFormatters: Validators.phoneInput,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: 'e.g. +91 98765 43210 (Spouse/Parent)',
                  prefixIcon: Icon(Icons.contact_phone_outlined,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 32),

              // Save Button
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryTeal,
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _saveProfile,
                      child: const Text('Save Profile & Preferred Doctors'),
                    ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ));
  }
}
