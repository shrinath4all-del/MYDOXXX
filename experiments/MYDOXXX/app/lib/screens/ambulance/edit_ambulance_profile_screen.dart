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
import '../../widgets/verification_documents_section.dart';
import '../../utils/validators.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/profile_photo_actions.dart';

class EditAmbulanceProfileScreen extends StatefulWidget {
  final UserModel ambulance;

  const EditAmbulanceProfileScreen({
    super.key,
    required this.ambulance,
  });

  @override
  State<EditAmbulanceProfileScreen> createState() =>
      _EditAmbulanceProfileScreenState();
}

class _EditAmbulanceProfileScreenState
    extends State<EditAmbulanceProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _vehicleController;
  late TextEditingController _phoneController;
  late TextEditingController _cityController;

  String? _profilePicUrl;

  // Verification Documents

  bool _isLoading = false;
  bool _uploadingPic = false;

  @override
  void initState() {
    super.initState();
    _profilePicUrl = widget.ambulance.profilePicUrl;

    _nameController = TextEditingController(text: widget.ambulance.name);
    _vehicleController = TextEditingController(
        text: widget.ambulance.vehicleNumber ?? '');
    _phoneController = TextEditingController(
        text: widget.ambulance.mobileNumber ?? widget.ambulance.phone ?? '');
    _cityController =
        TextEditingController(text: widget.ambulance.city ?? 'Pune');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _vehicleController.dispose();
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
          uid: widget.ambulance.uid, role: 'ambulance', oldUrl: old);
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
        uid: widget.ambulance.uid,
        file: picked,
      );

      await FirestoreService.updateUserProfilePicUrl(
        uid: widget.ambulance.uid,
        role: 'ambulance',
        photoUrl: url,
      );

      if (mounted) {
        setState(() {
          _profilePicUrl = url;
          _uploadingPic = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ambulance profile picture updated!'),
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
      final String pic = _profilePicUrl ?? '';

      final Map<String, dynamic> ambData = {
        'name': _nameController.text.trim(),
        'vehicleNumber': _vehicleController.text.trim(),
        'phone': _phoneController.text.trim(),
        'mobileNumber': _phoneController.text.trim(),
        if (pic.isNotEmpty) 'profilePicUrl': pic,
      };

      await AppDatabase.instance
          .collection('ambulances')
          .doc(widget.ambulance.uid)
          .set(ambData, SetOptions(merge: true));

      await FirestoreService.saveAccountRecord(ambData, widget.ambulance.uid);

      // the saved fields on top of everything else (verification, rating…)
      final updatedAmbulance = UserModel.fromMap(
          {...widget.ambulance.toMap(), ...ambData}, widget.ambulance.uid);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ambulance profile & service areas saved!'),
          backgroundColor: AppColors.successDark,
        ),
      );

      Navigator.of(context).pop(updatedAmbulance);
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
        title: const Text('Edit Ambulance Profile'),
        actions: [
          IconButton(
            icon: Icon(Icons.check_rounded, color: AppColors.primaryDark),
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
                                Icons.airport_shuttle_rounded,
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
                          decoration: BoxDecoration(
                            color: AppColors.primaryDark,
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
                role: 'ambulance',
                uid: widget.ambulance.uid,
                accentColor: AppColors.warning,
              ),

              const SizedBox(height: 20),

              // Live location info (no manual areas)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.my_location_rounded, color: AppColors.primary, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your live GPS location is used for dispatch. Keep location on while you are available.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Driver Name & Vehicle Number
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DRIVER NAME',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          validator: (v) => Validators.personName(v, label: 'driver name'),
                          decoration: const InputDecoration(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('VEHICLE NUMBER',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _vehicleController,
                          validator: Validators.vehicleNumber,
                          decoration: const InputDecoration(),
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
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _phoneController,
                          validator: Validators.mobile,
                          inputFormatters: Validators.phoneInput,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(),
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
                        backgroundColor: AppColors.primaryDark,
                      ),
                      onPressed: _saveProfile,
                      child: const Text('Save Ambulance Profile & Areas'),
                    ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ));
  }
}
