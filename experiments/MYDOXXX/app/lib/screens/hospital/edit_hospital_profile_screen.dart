import '../../services/app_database.dart';
import '../../widgets/circle_image.dart';
import '../../utils/form_utils.dart';
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

class EditHospitalProfileScreen extends StatefulWidget {
  final UserModel hospital;

  const EditHospitalProfileScreen({
    super.key,
    required this.hospital,
  });

  @override
  State<EditHospitalProfileScreen> createState() =>
      _EditHospitalProfileScreenState();
}

class _EditHospitalProfileScreenState
    extends State<EditHospitalProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _cityController;

  String? _profilePicUrl;
  String? _bombayNursingCertUrl;

  bool _isLoading = false;
  bool _uploadingPic = false;

  List<String> _availableHospitalServices = [];
  Set<String> _selectedOfferedServices = {};
  bool _loadingServices = true;

  // Areas ('location_master'), saved as preferredLocations
  Set<String> _selectedLocations = {};
  List<String> _allLocations = [];

  @override
  void initState() {
    super.initState();
    _profilePicUrl = widget.hospital.profilePicUrl;
    _bombayNursingCertUrl = widget.hospital.bombayNursingCertUrl;

    _nameController = TextEditingController(text: widget.hospital.name);
    _phoneController = TextEditingController(
        text: widget.hospital.mobileNumber ?? widget.hospital.phone ?? '');
    _cityController =
        TextEditingController(text: widget.hospital.city ?? 'Pune');

    _selectedLocations = {...?widget.hospital.preferredLocations};
    _allLocations = _selectedLocations.toList();

    _fetchHospitalServices();
  }

  /// Services and areas from the masters, then the hospital's saved
  /// services and areas from its own record.
  Future<void> _fetchHospitalServices() async {
    try {
      final results = await Future.wait<Object?>([
        FirestoreService.getHospitalServices(),
        FirestoreService.loadProfileForEdit('hospitals', widget.hospital.uid),
      ]);
      final services = results[0] as List<String>;
      final p = results[1]
          as ({Map<String, dynamic> data, List<String> areas});
      if (mounted) {
        setState(() {
          _selectedOfferedServices =
              FirestoreService.stringList(p.data['offeredServices']).toSet();
          _availableHospitalServices = [
            ...services,
            for (final s in _selectedOfferedServices)
              if (!services.contains(s)) s,
          ];
          if (p.data['preferredLocations'] is List) {
            _selectedLocations =
                FirestoreService.stringList(p.data['preferredLocations'])
                    .toSet();
          }
          _allLocations =
              FirestoreService.areaOptions(p.areas, _selectedLocations);
          _loadingServices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _availableHospitalServices =
              FirestoreService.defaultHospitalServices;
          _loadingServices = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  /// Remove the photo: the default icon shows again everywhere.
  Future<void> _removeProfilePic() async {
    final old = _profilePicUrl;
    setState(() => _uploadingPic = true);
    try {
      await FirestoreService.removeProfilePic(
          uid: widget.hospital.uid, role: 'hospital', oldUrl: old);
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
        uid: widget.hospital.uid,
        file: picked,
      );

      await FirestoreService.updateUserProfilePicUrl(
        uid: widget.hospital.uid,
        role: 'hospital',
        photoUrl: url,
      );

      if (mounted) {
        setState(() {
          _profilePicUrl = url;
          _uploadingPic = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hospital profile picture updated!'),
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

      final Map<String, dynamic> hospitalData = {
        'name': _nameController.text.trim(),
        'hospital': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'mobileNumber': _phoneController.text.trim(),
        // the area is part of the fixed location: not editable once locked
        if (widget.hospital.locationLocked != true)
          'city': _cityController.text.trim(),
        'offeredServices': _selectedOfferedServices.toList(),
        'preferredLocations': locs,
        if (pic.isNotEmpty) 'profilePicUrl': pic,
        if (_bombayNursingCertUrl != null)
          'bombayNursingCertUrl': _bombayNursingCertUrl,
      };

      await AppDatabase.instance
          .collection('hospitals')
          .doc(widget.hospital.uid)
          .set(hospitalData, SetOptions(merge: true));

      await FirestoreService.saveAccountRecord(hospitalData, widget.hospital.uid);

      // the saved fields on top of everything else (verification, rating…)
      final updatedHospital = UserModel.fromMap(
          {...widget.hospital.toMap(), ...hospitalData}, widget.hospital.uid);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hospital profile & services updated!'),
          backgroundColor: AppColors.successDark,
        ),
      );

      Navigator.of(context).pop(updatedHospital);
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
        title: const Text('Edit Hospital Profile'),
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
  backgroundColor: AppColors.primaryTint,
  fallback: const Icon(
                                Icons.local_hospital_rounded,
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
                role: 'hospital',
                uid: widget.hospital.uid,
                accentColor: AppColors.primary,
              ),

              const SizedBox(height: 24),

              // OFFERED HOSPITAL SERVICES CHECKBOXES SECTION (From Firestore 'hospital_services')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryBorder),
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
                          'Hospital Emergency Facilities',
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
                      'Check the facilities available at your hospital (Fetched from hospital_services):',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),

                    if (_loadingServices)
                      const CircularProgressIndicator(color: AppColors.primary)
                    else
                      Column(
                        children: _availableHospitalServices.map((serviceName) {
                          final bool isChecked =
                              _selectedOfferedServices.contains(serviceName);

                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            activeColor: AppColors.primary,
                            title: Text(
                              serviceName,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedOfferedServices.add(serviceName);
                                } else {
                                  _selectedOfferedServices.remove(serviceName);
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

              // PREFERRED SERVICE LOCATIONS
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
                          'Hospital Service Areas',
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
                      'Select the areas where your hospital accepts emergency admissions:',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),

                    AreaMultiSelectField(
                      loading: _loadingServices,
                      areas: _allLocations,
                      selected: _selectedLocations,
                      onChanged: (v) => setState(() => _selectedLocations = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Hospital Name & Phone
              const Text('Hospital Name',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) => Validators.orgName(v, label: 'hospital name'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.local_hospital_outlined,
                      color: AppColors.primary),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Emergency Phone',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                validator: (v) => Validators.contactNumber(v),
                inputFormatters: Validators.phoneInput,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  prefixIcon:
                      Icon(Icons.phone_outlined, color: AppColors.primary),
                ),
              ),

              const SizedBox(height: 16),

              const Text('City / Area',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _cityController,
                validator: Validators.city,
                readOnly: widget.hospital.locationLocked == true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.location_city_outlined,
                      color: AppColors.primary),
                  suffixIcon: widget.hospital.locationLocked == true
                      ? const Icon(Icons.lock_rounded, size: 18)
                      : null,
                  helperText: widget.hospital.locationLocked == true
                      ? 'Hospital location is fixed and cannot be changed.'
                      : null,
                ),
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
                      child: const Text('Save Hospital Profile & Services'),
                    ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ));
  }
}
