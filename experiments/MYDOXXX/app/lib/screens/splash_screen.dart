import '../services/agency_invite_service.dart';
import 'auth/register_screen.dart';
import 'package:flutter/material.dart';

import '../widgets/delete_account_button.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'admin/admin_home_screen.dart';
import 'agency/agency_home_screen.dart';
import 'care_physician/care_physician_home_screen.dart';
import 'ambulance/ambulance_home_screen.dart';
import 'auth/login_screen.dart';
import 'doctor/doctor_home_screen.dart';
import 'hospital/hospital_home_screen.dart';
import 'nurse/nurse_staffing_screen.dart';
import 'patient/patient_home_screen.dart';
import 'technician/technician_staffing_screen.dart';
import 'therapist/therapist_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  // Signed in, but the account could not be loaded (e.g. no internet). The
  // user stays signed in: only the Sign out button ends the session.
  bool _loadFailed = false;
  bool _retrying = false;

  Future<void> _checkAuthState() async {
    try {
      // Wait for Firebase to restore the saved login (the web needs a moment)
      final user = await _authService.authStateChanges.first
          .timeout(const Duration(seconds: 5), onTimeout: () => _authService.currentUser);
      if (!mounted) return;
      if (user == null) {
        _navigateToLogin(); // not signed in: straight to login
        return;
      }
    } catch (_) {}
    if (!mounted) return;

    try {
      var loaded = await _authService.getCurrentUserModel();
      // A bad connection must never look like being logged out: try a few
      // times before giving up (and then offer Retry, not the login screen).
      if (loaded == null && _authService.currentUser != null) {
        for (var i = 0; i < 3 && loaded == null; i++) {
          await Future.delayed(Duration(seconds: 1 + i));
          if (!mounted) return;
          loaded = await _authService.getCurrentUserModel();
        }
        if (loaded == null) {
          if (mounted) setState(() => _loadFailed = true);
          return;
        }
      }
      if (!mounted) return;
      var kept = loaded;
      // deleted less than 30 days ago: keep it, or back to the login screen
      if (kept != null) {
        if (!await checkScheduledDeletion(context)) {
          if (mounted) _navigateToLogin();
          return;
        }
        if (!mounted) return;
        kept = await _authService.getCurrentUserModel() ?? kept;
        if (!mounted) return;
      }
      final userModel = kept;
      if (userModel != null) SessionService.appReady = true; // home opens next

      if (userModel != null) {
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
        } else if (userModel.isNurse) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => NurseStaffingScreen(user: userModel),
            ),
          );
        } else if (userModel.isTherapist) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TherapistHomeScreen(therapist: userModel),
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
      }
    } catch (_) {
      // Signed in but the account could not be loaded: offer Retry
      if (mounted && _authService.currentUser != null) {
        setState(() => _loadFailed = true);
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _loadFailed = false;
    });
    await _checkAuthState();
    if (mounted) setState(() => _retrying = false);
  }

  void _navigateToLogin() {
    SessionService.appReady = true;
    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    // a referral / agency invite link opens sign-up at once, with who sent
    // it filled in (Login stays underneath for people who have an account)
    if ((AgencyInviteService.pendingFromLink ?? '').isNotEmpty) {
      navigator.push(MaterialPageRoute(
          builder: (_) =>
              const RegisterScreen(initialRole: 'care_physician')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.medical_services_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'MyDox',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_loadFailed || _retrying)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'We could not load your account. Check your internet connection. You are still signed in.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white, fontSize: 14, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            _retrying
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _retry,
                                          child: const Text('Retry'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      TextButton(
                                        onPressed: () async {
                                          await _authService.signOut();
                                          if (mounted) _navigateToLogin();
                                        },
                                        child: const Text('Sign out',
                                            style: TextStyle(
                                                color: Colors.white70)),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    )
                  else
                    const CircularProgressIndicator(color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
