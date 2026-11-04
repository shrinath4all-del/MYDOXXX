import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/test_lab_config.dart';
import '../../models/user_model.dart';
import '../../services/app_database.dart';
import '../../services/session_service.dart';
import '../agency/agency_home_screen.dart';
import '../ambulance/ambulance_home_screen.dart';
import '../care_physician/care_physician_home_screen.dart';
import '../doctor/doctor_home_screen.dart';
import '../hospital/hospital_home_screen.dart';
import '../nurse/nurse_staffing_screen.dart';
import '../patient/patient_home_screen.dart';
import '../technician/technician_staffing_screen.dart';
import '../therapist/therapist_home_screen.dart';
import 'test_lab_cloud_bridge_stub.dart'
    if (dart.library.js_interop) 'test_lab_cloud_bridge_web.dart'
    as cloud_bridge;

class TestLabLoginScreen extends StatefulWidget {
  const TestLabLoginScreen({super.key});
  @override
  State<TestLabLoginScreen> createState() => _TestLabLoginScreenState();
}

class _TestLabLoginScreenState extends State<TestLabLoginScreen> {
  bool _busy = false;
  String? _error;
  String _stage = 'Connecting';

  Future<T> _step<T>(String label, Future<T> Function() action) async {
    if (mounted) setState(() => _stage = label);
    try {
      return await action().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw StateError(
          'Timed out while $label. Check the connection and retry.');
    }
  }

  String get _key => Uri.base.queryParameters['role'] ?? '';
  String get _label => TestLabConfig.labels[_key] ?? 'test role';

  @override
  void initState() {
    super.initState();
    if (Uri.base.queryParameters['autologin'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _login());
    }
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    SessionService.pause();
    try {
      TestLabConfig.requireEnvironment(Uri.base);
      final Map<String, dynamic> config;
      if (TestLabConfig.cloudEnabled) {
        if (!TestLabConfig.labels.containsKey(_key)) {
          throw StateError('Open a supported role from the cloud test portal.');
        }
        final response = await _step('Authorizing cloud test role',
            () => cloud_bridge.requestCloudLogin(_key));
        config = jsonDecode(response) as Map<String, dynamic>;
        TestLabConfig.validateCloudLoginConfig(config, requestedRole: _key);
      } else {
        final response = await _step(
            'Loading local test login',
            () => http.get(
                  Uri.base.resolve('/__mydox_test__/login-config'),
                  headers: const {
                    'X-MyDox-Test-Client': '1',
                    'Cache-Control': 'no-store'
                  },
                ));
        if (response.statusCode != 200) {
          throw StateError(
              'Start the local test console, then reopen this role panel.');
        }
        config = jsonDecode(response.body) as Map<String, dynamic>;
        TestLabConfig.validateLoginConfig(config, requestedRole: _key);
      }
      final auth = FirebaseAuth.instance;
      await _step(
          'Isolating this panel', () => auth.setPersistence(Persistence.NONE));
      await _step('Clearing previous test login', auth.signOut);
      final credential = await _step(
          'Signing in to Firebase',
          () => TestLabConfig.cloudEnabled
              ? auth.signInWithCustomToken(config['customToken'] as String)
              : auth.signInWithEmailAndPassword(
                  email: config['email'] as String,
                  password: config['password'] as String,
                ));
      // The ephemeral credential is no longer needed after Firebase sign-in.
      config.remove('customToken');
      config.remove('password');
      final user = credential.user;
      if (user == null) {
        throw StateError('Firebase did not return a test identity.');
      }
      final token = await _step(
          'Checking assigned test role', () => user.getIdTokenResult(true));
      final claims = token.claims ?? {};
      if (user.uid != config['uid'] ||
          claims['mydoxTest'] != true ||
          claims['testDatabase'] != TestLabConfig.databaseId ||
          claims['role'] != config['role']) {
        throw StateError(
            'This account is not assigned to this synthetic test role.');
      }
      if (TestLabConfig.cloudEnabled) {
        TestLabConfig.validateCloudClaims(claims);
      }
      final collection = switch (config['role']) {
        'patient' => 'patients',
        'doctor' => 'doctors',
        'hospital' => 'hospitals',
        'nurse' => 'nurses',
        'technician' => 'technicians',
        'therapist' => 'therapists',
        'ambulance' => 'ambulances',
        'care_physician' => 'care_physicians',
        'agency' => 'agencies',
        _ => throw StateError('Unsupported test role.'),
      };
      final profile = await _step(
          'Loading synthetic profile',
          () => AppDatabase.instance
              .collection(collection)
              .doc(user.uid)
              .get(const GetOptions(source: Source.server)));
      final data = profile.data();
      if (data == null ||
          data['mydoxSynthetic'] != true ||
          data['role'] != config['role']) {
        throw StateError(
            'The synthetic profile is not ready. Retry after test setup.');
      }
      final model = UserModel.fromMap(data, user.uid);
      // Test identities intentionally allow simultaneous panels for one role.
      // The production one-device session policy is not applied in this lab.
      SessionService.appReady = true;
      SessionService.resume();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => _workspace(model),
      ));
    } catch (e) {
      try {
        await FirebaseAuth.instance
            .signOut()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      SessionService.resume();
      if (!mounted) return;
      setState(() {
        _error = e is StateError
            ? e.message.toString()
            : e is FirebaseAuthException
                ? 'Test sign-in failed (${e.code}). Reopen the test panel and retry.'
                : 'The test connection is not ready. Reopen the test panel and retry.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _workspace(UserModel u) => switch (u.role) {
        'patient' => PatientHomeScreen(patient: u),
        'doctor' => DoctorHomeScreen(doctor: u),
        'nurse' => NurseStaffingScreen(user: u),
        'hospital' => HospitalHomeScreen(hospital: u),
        'ambulance' => AmbulanceHomeScreen(ambulance: u),
        'care_physician' => CarePhysicianHomeScreen(user: u),
        'technician' => TechnicianStaffingScreen(user: u),
        'therapist' => TherapistHomeScreen(therapist: u),
        'agency' => AgencyHomeScreen(agency: u),
        _ => const SizedBox.shrink(),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xffeff7f7),
        body: Center(
            child: SingleChildScrollView(
                child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.devices_rounded,
                size: 54, color: Color(0xff008b79)),
            const SizedBox(height: 18),
            Text('MYDOXXX • $_label',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
                'Shared Firebase test lab\nSynthetic people and bookings only',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login_rounded),
                label: Text(_busy ? _stage : 'Open $_label')),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 20),
            const Text(
                'SMS, payments, external calls, uploads and real GPS are disabled.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12)),
          ]),
        ))),
      );
}

class TestLabBanner extends StatelessWidget {
  const TestLabBanner({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
            color: const Color(0xff16384b),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text(
                      'TEST • ${TestLabConfig.labels[Uri.base.queryParameters['role']] ?? 'MYDOXXX'} • Shared synthetic data',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            )),
        Expanded(child: child),
      ]);
}
