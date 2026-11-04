import '../../config/test_lab_config.dart';
import '../test_lab/test_lab_login_screen.dart';
import 'package:flutter/material.dart';
import '../../utils/form_utils.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../admin/admin_home_screen.dart';
import '../agency/agency_home_screen.dart';
import '../care_physician/care_physician_home_screen.dart';
import '../ambulance/ambulance_home_screen.dart';
import '../doctor/doctor_home_screen.dart';
import '../hospital/hospital_home_screen.dart';
import '../nurse/nurse_staffing_screen.dart';
import '../patient/patient_home_screen.dart';
import '../technician/technician_staffing_screen.dart';
import '../therapist/therapist_home_screen.dart';
import 'register_screen.dart';
import '../../utils/error_messages.dart';
import '../../widgets/otp_dialog.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../constants/app_strings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final TextEditingController _phoneController = TextEditingController();

  String _selectedRole = 'patient'; // 'patient', 'doctor', 'technician'
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// Login. If the account is signed in on another device, ask before
  /// replacing it (only one device at a time, never signed out silently).
  Future<UserModel?> _loginAskingAboutOtherDevice() async {
    try {
      return await _authService.loginWithVerifiedPhone(expectedRole: _selectedRole);
    } on SessionConflictException catch (c) {
      if (!mounted) return null;
      final since = c.since == null
          ? ''
          : ' since ${c.since!.day}/${c.since!.month} ${c.since!.hour.toString().padLeft(2, '0')}:${c.since!.minute.toString().padLeft(2, '0')}';
      final move = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.devices_other_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(child: Text('Already signed in elsewhere')),
            ],
          ),
          content: Text(
            'This account is signed in on another device (${c.device}$since). '
            'Only one device can be signed in at a time.\n\n'
            'Sign out there and continue on this device?',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out there & continue'),
            ),
          ],
        ),
      );
      if (move != true) {
        await _authService.signOut();
        return null;
      }
      return _authService.loginWithVerifiedPhone(
          expectedRole: _selectedRole, takeOver: true);
    }
  }

  Future<void> _handleLogin() async {
    if (!FormUtils.validate(_formKey)) return;

    final phoneError = Validators.mobile(_phoneController.text);
    if (phoneError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(phoneError), backgroundColor: AppColors.danger),
      );
      return;
    }

    // 1) OTP to the mobile number, 2) open the profile for the chosen role
    final verified = await showPhoneOtpDialog(context,
        authService: _authService, phone: _phoneController.text);
    if (!verified || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final userModel = await _loginAskingAboutOtherDevice();
      if (userModel == null) return; // the user kept the other device signed in

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, ${userModel.name}!'),
          backgroundColor: AppColors.brand,
        ),
      );

      if (userModel.isAdmin) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminHomeScreen(admin: userModel),
          ),
        );
      } else if (userModel.isHospital) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HospitalHomeScreen(hospital: userModel),
          ),
        );
      } else if (userModel.isAmbulance) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AmbulanceHomeScreen(ambulance: userModel),
          ),
        );
      } else if (userModel.isDoctor) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DoctorHomeScreen(doctor: userModel),
          ),
        );
      } else if (userModel.isTechnician) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TechnicianStaffingScreen(user: userModel),
          ),
        );
      } else if (userModel.isTherapist) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TherapistHomeScreen(therapist: userModel),
          ),
        );
      } else if (userModel.isNurse) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => NurseStaffingScreen(user: userModel),
          ),
        );
      } else if (userModel.isCarePhysician) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CarePhysicianHomeScreen(user: userModel),
          ),
        );
      } else if (userModel.isAgency) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AgencyHomeScreen(agency: userModel),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PatientHomeScreen(patient: userModel),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.of(e, action: 'log in')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildRoleButton(String role, String label, IconData icon) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedRole = role);
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
    if (TestLabConfig.enabled) return const TestLabLoginScreen();
    return ResponsiveCenter(child: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Header Card with Gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                  top: 60, bottom: 40, left: 24, right: 24),
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medical_services_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Welcome to MyDox',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to access your healthcare portal',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                // Only show field errors on submit
                autovalidateMode: AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role Toggle Selector (Patient vs Doctor vs Technician)
                    const Text(
                      'I am a:',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                            _buildRoleButton('patient', 'Patient', Icons.person_outline_rounded),
                            const SizedBox(width: 4),
                            _buildRoleButton('hospital', 'Hospital', Icons.local_hospital_rounded),
                            const SizedBox(width: 4),
                            _buildRoleButton('doctor', 'Doctor', Icons.health_and_safety_outlined),
                            const SizedBox(width: 4),
                            _buildRoleButton('ambulance', 'Ambulance', Icons.airport_shuttle_rounded),
                            const SizedBox(width: 4),
                            _buildRoleButton('technician', AppStrings.roleName('technician'), Icons.science_outlined),
                            const SizedBox(width: 4),
                            _buildRoleButton('therapist', 'Therapist', Icons.self_improvement_rounded),
                            const SizedBox(width: 4),
                            _buildRoleButton('nurse', 'Nurse', Icons.local_hospital_outlined),
                            const SizedBox(width: 4),
                            _buildRoleButton('care_physician', 'Care Physician', Icons.medical_information_outlined),
                            const SizedBox(width: 4),
                            _buildRoleButton('agency', AppStrings.roleName('agency'), Icons.business_rounded),
                            const SizedBox(width: 4),
                            _buildRoleButton('admin', 'Admin', Icons.admin_panel_settings_outlined),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Mobile number
                    const Text(
                      'Mobile Number',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _phoneController,
                      validator: Validators.mobile,
                      inputFormatters: Validators.phoneInput,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '+91 98765 43210',
                        prefixIcon: Icon(Icons.phone_android_outlined,
                            color: AppColors.brand),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'We will send a 6-digit OTP to this number.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),

                    const SizedBox(height: 24),

                    // Submit Login Button
                    _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.brand,
                            ),
                          )
                        : ElevatedButton(
                            onPressed: _handleLogin,
                            // hospital / ambulance used to say "Login as Patient"
                            child: Text(AppStrings.loginAs(_selectedRole)),
                          ),

                    const SizedBox(height: 16),

                    const SizedBox(height: 24),

                    // Register Switch Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RegisterScreen(
                                  initialRole: _selectedRole,
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Register Now',
                            style: TextStyle(
                              color: AppColors.brand,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
