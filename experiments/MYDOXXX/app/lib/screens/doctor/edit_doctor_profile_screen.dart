import '../../services/app_database.dart';
import '../../widgets/circle_image.dart';
import '../../widgets/delete_account_button.dart';
import '../../utils/form_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/verification_documents_section.dart';
import '../../utils/validators.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/profile_photo_actions.dart';

class EditDoctorProfileScreen extends StatefulWidget {
  final UserModel doctor;

  const EditDoctorProfileScreen({
    super.key,
    required this.doctor,
  });

  @override
  State<EditDoctorProfileScreen> createState() =>
      _EditDoctorProfileScreenState();
}

class _EditDoctorProfileScreenState extends State<EditDoctorProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late TextEditingController _nameController;
  late TextEditingController _hospitalController;
  late TextEditingController _hospitalAddressController;
  late TextEditingController _mobileController;
  late TextEditingController _experienceController;
  late TextEditingController _qualificationController;

  String? _selectedCategory;
  String? _profilePicUrl;

  // Verification Documents URLs

  List<String> _categories = [];
  bool _loadingCategories = true;

  String? _selectedDoctorArea;

  List<Map<String, dynamic>> _registeredHospitals = [];
  Map<String, dynamic>? _selectedHospitalMap;

  bool _isLoading = false;
  bool _uploadingPic = false;

  @override
  void initState() {
    super.initState();
    _profilePicUrl = widget.doctor.profilePicUrl;

    if (widget.doctor.preferredLocations != null &&
        widget.doctor.preferredLocations!.isNotEmpty) {
      _selectedDoctorArea = widget.doctor.preferredLocations!.first;
    } else if (widget.doctor.city != null && widget.doctor.city!.isNotEmpty) {
      _selectedDoctorArea = widget.doctor.city;
    }

    _nameController = TextEditingController(text: widget.doctor.name);
    _hospitalController =
        TextEditingController(text: widget.doctor.hospital ?? '');
    _hospitalAddressController =
        TextEditingController(text: widget.doctor.homeAddress ?? '');
    _mobileController =
        TextEditingController(text: widget.doctor.mobileNumber ?? '');
    _experienceController =
        TextEditingController(text: widget.doctor.experience ?? '');
    _qualificationController =
        TextEditingController(text: widget.doctor.qualification ?? '');

    _fetchCategories();
    _fetchHospitals();
  }

  Future<void> _fetchHospitals() async {
    try {
      final list = await FirestoreService.getHospitalsList();
      if (mounted) {
        setState(() {
          _registeredHospitals = list;
          // only the doctor's saved hospital, never a guess (saving a guess
          // would move the doctor to another hospital)
          final saved = (widget.doctor.hospital ?? '').toLowerCase();
          final match = saved.isEmpty
              ? const <Map<String, dynamic>>[]
              : _registeredHospitals.where((h) =>
                  (h['name'] ?? h['hospital'] ?? '').toString().toLowerCase() ==
                  saved);
          _selectedHospitalMap = match.isEmpty ? null : match.first;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchCategories() async {
    try {
      final fetched = await FirestoreService.getDoctorCategories();
      if (mounted) {
        setState(() {
          _categories = fetched;
          if (widget.doctor.category != null &&
              _categories.contains(widget.doctor.category)) {
            _selectedCategory = widget.doctor.category;
          } else if (_categories.isNotEmpty) {
            _selectedCategory = _categories.first;
          }
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          // categories come only from Firestore: keep the saved one
          _categories = [
            if ((widget.doctor.category ?? '').isNotEmpty) widget.doctor.category!,
          ];
          _selectedCategory = _categories.isEmpty ? null : _categories.first;
          _loadingCategories = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hospitalController.dispose();
    _hospitalAddressController.dispose();
    _mobileController.dispose();
    _experienceController.dispose();
    _qualificationController.dispose();
    super.dispose();
  }

  /// Remove the photo: the default icon shows again everywhere.
  Future<void> _removeProfilePic() async {
    final old = _profilePicUrl;
    setState(() => _uploadingPic = true);
    try {
      await FirestoreService.removeProfilePic(
          uid: widget.doctor.uid, role: 'doctor', oldUrl: old);
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
        uid: widget.doctor.uid,
        file: picked,
      );

      await FirestoreService.updateUserProfilePicUrl(
        uid: widget.doctor.uid,
        role: 'doctor',
        photoUrl: url,
      );

      if (mounted) {
        setState(() {
          _profilePicUrl = url;
          _uploadingPic = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doctor profile picture updated!'),
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

    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String hospName = _selectedHospitalMap?['name'] ??
          _selectedHospitalMap?['hospital'] ??
          _hospitalController.text.trim();

      final String area = (_selectedHospitalMap?['preferredLocations']
                  as List<dynamic>?)
              ?.first
              ?.toString() ??
          _selectedHospitalMap?['city'] ??
          _selectedDoctorArea ??
          '';

      final String hospAddress = _selectedHospitalMap?['homeAddress'] ??
          _selectedHospitalMap?['exactAddress'] ??
          _hospitalAddressController.text.trim();

      final Map<String, dynamic> locUpdate = {
        'hospital': hospName,
        if (area.isNotEmpty) 'preferredLocations': [area],
        if (area.isNotEmpty) 'city': area,
        'homeAddress': hospAddress,
      };

      await AppDatabase.instance
          .collection('doctors')
          .doc(widget.doctor.uid)
          .set(locUpdate, SetOptions(merge: true));


      final updatedDoctor = await _authService.updateDoctorProfile(
        uid: widget.doctor.uid,
        name: _nameController.text,
        category: _selectedCategory!,
        hospital: hospName,
        mobileNumber: _mobileController.text,
        experience: _experienceController.text,
        qualification: _qualificationController.text,
        profilePicUrl: _profilePicUrl,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Doctor profile updated successfully!'),
          backgroundColor: AppColors.successDark,
        ),
      );

      Navigator.of(context).pop(updatedDoctor);
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
        title: const Text('Edit Doctor Profile'),
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
              // Avatar
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
                                Icons.medical_services_rounded,
                                size: 48,
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

              // VERIFICATION DOCUMENTS (role-specific list from Firestore 'verification_requirements')
              VerificationDocumentsSection(
                role: 'doctor',
                uid: widget.doctor.uid,
                accentColor: AppTheme.primaryTeal,
              ),

              const SizedBox(height: 24),

              // 1. Doctor Name
              const Text('Doctor Name',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) => Validators.personName(v, label: 'doctor name'),
                decoration: const InputDecoration(
                  hintText: 'e.g. Dr. Elizabeth Amelia',
                  prefixIcon: Icon(Icons.badge_outlined,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // 2. Doctor Category Dropdown
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
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryTeal,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Loading categories...'),
                        ],
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      // long lists scroll instead of covering the form
                      menuMaxHeight: 320,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.category_outlined,
                            color: AppTheme.primaryTeal),
                      ),
                      items: _categories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedCategory = val);
                      },
                    ),

              const SizedBox(height: 16),

              // 3. Associated Hospital Dropdown (Fetched from Firestore 'hospitals')
              const Text('Associated Hospital',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedHospitalMap,
                menuMaxHeight: 320,
                hint: const Text('Choose your hospital'),
                validator: (v) => v == null &&
                        (widget.doctor.hospital ?? '').isEmpty
                    ? 'Please choose your hospital'
                    : null,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.local_hospital_outlined,
                      color: AppTheme.primaryTeal),
                ),
                items: _registeredHospitals.map((hMap) {
                  final hName = hMap['name'] ?? hMap['hospital'] ?? 'Hospital';
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: hMap,
                    child: Text(hName.toString()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedHospitalMap = value;
                  });
                },
              ),

              if (_selectedHospitalMap != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Address: ${_selectedHospitalMap!['homeAddress'] ?? _selectedHospitalMap!['exactAddress'] ?? '—'}',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // 4. Mobile Number
              const Text('Doctor Mobile Number',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _mobileController,
                validator: Validators.mobile,
                inputFormatters: Validators.phoneInput,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: '+91 98765 43210',
                  prefixIcon: Icon(Icons.phone_android_outlined,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // 5. Qualification
              const Text('Medical Qualification',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _qualificationController,
                validator: (v) => Validators.qualification(v),
                decoration: const InputDecoration(
                  hintText: 'e.g. MBBS, MD, FACC',
                  prefixIcon: Icon(Icons.school_outlined,
                      color: AppTheme.primaryTeal),
                ),
              ),

              const SizedBox(height: 16),

              // 6. Experience
              const Text('Years of Experience',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _experienceController,
                keyboardType: TextInputType.number,
                validator: Validators.experience,
                decoration: const InputDecoration(
                  hintText: 'e.g. 8',
                  prefixIcon: Icon(Icons.work_history_outlined,
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
                      child: const Text('Save Profile Changes'),
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
