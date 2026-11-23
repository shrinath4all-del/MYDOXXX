import 'app_database.dart';
import '../config/experiment_environment.dart';
import '../utils/ist_clock.dart';
import '../utils/admin_login_policy.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import '../utils/validators.dart';
import 'care_physician_service.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import 'firestore_service.dart';
import 'push_service.dart';
import 'location_tracker.dart';
import 'session_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = AppDatabase.instance;

  // Stream of currentUser
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// The one administrator account (create it in Firebase Authentication with
  /// this email and a password).
  static const String adminEmail = 'kunal123@gmail.com';

  /// Turns whatever was typed into E.164. A bare 10-digit number is treated
  /// as an Indian mobile (+91).
  static String normalizePhone(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (trimmed.startsWith('+')) return '+$digits';
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+91${digits.substring(1)}';
    }
    return '+$digits';
  }

  /// Converts raw FirebaseAuthException into user-friendly error messages
  static String handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That mobile number is not valid. Enter it with country code, e.g. +91 98765 43210.';
      case 'invalid-verification-code':
        return 'Wrong OTP. Please check the code and try again.';
      case 'session-expired':
      case 'code-expired':
        return 'This OTP has expired. Please request a new one.';
      case 'invalid-verification-id':
        return 'OTP session is no longer valid. Please request a new OTP.';
      case 'quota-exceeded':
        return 'SMS limit reached for now. Please try again later.';
      // Firebase's own code and text are shown too, so the exact failed
      // check (fingerprint, Play Integrity, reCAPTCHA domain) is visible
      case 'captcha-check-failed':
      case 'invalid-app-credential':
        return 'Phone verification was rejected (reCAPTCHA / app check failed). On web, open the app at localhost (not 127.0.0.1) or the web.app address; on Android, the SHA-1 and SHA-256 of the key that signed this APK must be in Firebase. [${e.code}: ${e.message ?? ''}]';
      case 'missing-client-identifier':
      case 'app-not-authorized':
        return 'This app is not authorized for phone sign-in. On Android, add the SHA-1 and SHA-256 of the key that signed this APK in Firebase project settings. [${e.code}: ${e.message ?? ''}]';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'operation-not-allowed':
        // Either the Phone provider is off for this project, or the SMS
        // region policy blocks the country. Firebase's own text says which.
        return 'Phone sign-in was rejected by Firebase: ${e.message ?? 'operation not allowed'}';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'wrong-password':
      case 'user-not-found':
        return 'Wrong email or password. Check both, or tap "Forgot password?" to set a new password.';
      case 'too-many-requests':
        return 'Too many wrong tries. Wait a few minutes, or tap "Forgot password?" to set a new password.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  // ------------------------------------------------------------ phone + OTP

  ConfirmationResult? _confirmation; // web
  String? _verificationId; // Android / iOS
  int? _resendToken;

  /// Sends a 6-digit SMS code to [phone] (Firebase phone authentication).
  /// Web uses an invisible reCAPTCHA; Android / iOS use verifyPhoneNumber.
  /// Last OTP sent from this device: reopening the OTP box within
  /// [otpReuseWindow] uses that code instead of asking Firebase again
  /// (every request counts towards Firebase's "too many attempts" block).
  static String? _lastOtpPhone;
  static DateTime? _lastOtpAt;
  static const Duration otpReuseWindow = Duration(seconds: 30);

  /// Whether a new OTP for [phone] would only repeat one just sent.
  static bool otpJustSent(String phone, {DateTime? now}) =>
      _lastOtpPhone == phone &&
      _lastOtpAt != null &&
      (now ?? IstClock.now()).difference(_lastOtpAt!) < otpReuseWindow;

  Future<void> sendOtp(String phone) async {
    ExperimentEnvironment.requireExternalActions();
    final normalized = normalizePhone(phone);
    // Firebase cannot send phone OTPs from a Windows desktop app
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      throw Exception(
          'Phone sign-in is not available in the Windows app. Please open MyDox in the experimental browser build or use the experimental mobile app.');
    }
    if (otpJustSent(normalized) &&
        (kIsWeb ? _confirmation != null : _verificationId != null)) {
      return; // the code sent a moment ago is still valid
    }
    try {
      if (kIsWeb) {
        try {
          _confirmation = await _auth.signInWithPhoneNumber(normalized);
        } on FirebaseAuthException catch (e) {
          // A stale or expired reCAPTCHA token (after a hot restart, a slow
          // click or a blocked widget) is rejected once; each call builds a
          // fresh reCAPTCHA, so one automatic retry clears it.
          if (e.code != 'invalid-app-credential' &&
              e.code != 'captcha-check-failed') {
            rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
          _confirmation = await _auth.signInWithPhoneNumber(normalized);
        }
        _lastOtpPhone = normalized;
        _lastOtpAt = IstClock.now();
        return;
      }

      final sent = Completer<void>();
      await _auth.verifyPhoneNumber(
        phoneNumber: normalized,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        // The code is always typed by the user, so instant verification is
        // not used to sign in automatically.
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          if (!sent.isCompleted) sent.completeError(e);
        },
        codeSent: (id, token) {
          _verificationId = id;
          _resendToken = token;
          _lastOtpPhone = normalized;
          _lastOtpAt = IstClock.now();
          if (!sent.isCompleted) sent.complete();
        },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
      );
      await sent.future;
    } on FirebaseAuthException catch (e) {
      throw Exception(handleAuthException(e));
    }
  }

  /// Checks the SMS code; on success the user is signed in.
  Future<void> verifyOtp(String code) async {
    // The device is about to sign in: don't let the old session id of this
    // account (from another device) sign it out before login completes.
    SessionService.pause();
    try {
      if (kIsWeb) {
        final c = _confirmation;
        if (c == null) throw Exception('Please request an OTP first.');
        await c.confirm(code.trim());
        return;
      }
      final id = _verificationId;
      if (id == null) throw Exception('Please request an OTP first.');
      await _auth.signInWithCredential(
        PhoneAuthProvider.credential(verificationId: id, smsCode: code.trim()),
      );
    } on FirebaseAuthException catch (e) {
      SessionService.resume();
      throw Exception(handleAuthException(e));
    }
  }

  // ------------------------------------------------------ email + password

  /// Creates the account for a new user (registration): they are signed in as
  /// soon as it exists, then [registerDoctor] and the other register methods
  /// save the profile for this uid. The mobile number is collected on the
  /// form but not verified.
  Future<void> createAccount(String email, String password) async {
    ExperimentEnvironment.requireExternalActions();
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email.trim().toLowerCase(), password: password);
    } on FirebaseAuthException catch (e) {
      throw Exception(handleAuthException(e));
    }
  }

  /// The last 10 digits of an Indian mobile number ("+91 98765-43210" ->
  /// "9876543210"), the form numbers are compared in.
  static String phoneKey(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  /// Whether [phone] already belongs to another account (any role), so one
  /// mobile number has one account. Checked right after the new login is
  /// created, before its profile is saved.
  Future<bool> isPhoneTaken(String phone) async {
    final key = phoneKey(phone);
    if (key.length != 10) return false;
    final me = _auth.currentUser?.uid;
    final forms = [key, '+91$key', '91$key', '0$key', '+91 $key'];
    for (final col in {..._roleCollections.values, 'users'}) {
      for (final field in ['phone', 'mobileNumber', 'phoneKey']) {
        final snap = await _db
            .collection(col)
            .where(field, whereIn: forms)
            .limit(2)
            .get();
        if (snap.docs.any((d) => d.id != me)) return true;
      }
    }
    return false;
  }

  /// Registration failed after the account was created: remove it again so
  /// the person can register again with the same email.
  Future<void> discardNewAccount() async {
    ExperimentEnvironment.requireExternalActions();
    try {
      await _auth.currentUser?.delete();
    } catch (_) {
      // not critical: signing out below leaves the account unused
    }
    await _auth.signOut();
  }

  /// Where a password link opens: the app's own "Set a new password" page
  /// (this experiment's own site, never the original project's).
  static const String resetPageUrl =
      'https://mydoxxx-dev-261102.web.app/reset-password';

  /// How long a password link may be used.
  static const int resetLinkMinutes = 15;

  /// Link settings: the email's link opens [resetPageUrl] with the code.
  static ActionCodeSettings get resetLinkSettings =>
      ActionCodeSettings(url: resetPageUrl, handleCodeInApp: true);

  /// Emails a link to choose a new password, valid for [resetLinkMinutes]
  /// minutes ([auth] = another sign-in instance, e.g. the admin's helper).
  static Future<void> sendResetLink(String email, {FirebaseAuth? auth}) async {
    ExperimentEnvironment.requireExternalActions();
    final clean = email.trim().toLowerCase();
    try {
      await (auth ?? FirebaseAuth.instance)
          .sendPasswordResetEmail(email: clean, actionCodeSettings: resetLinkSettings);
    } on FirebaseAuthException catch (e) {
      throw Exception(handleAuthException(e));
    }
    await markResetSent(clean);
  }

  /// The server notes when the newest link was sent (for the 15 minutes).
  static Future<void> markResetSent(String email) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('passwordReset')
          .call({'action': 'sent', 'email': email.trim().toLowerCase()});
    } catch (_) {
      // the link still works; only the 15-minute limit cannot be applied
    }
  }

  /// Whether the newest link for [email] is still within 15 minutes.
  static Future<bool> resetLinkFresh(String email) async {
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('passwordReset')
          .call({'action': 'check', 'email': email.trim().toLowerCase()});
      return (r.data as Map?)?['ok'] != false;
    } catch (_) {
      return true; // cannot check: Firebase's own expiry still applies
    }
  }

  /// Emails a link to choose a new password.
  Future<void> sendPasswordReset(String email) => sendResetLink(email);

  /// UID of the user who just verified their phone (registration step).
  String _requireVerifiedUid() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Phone verification is required before registering.');
    }
    return user.uid;
  }

  /// After OTP at registration: true if this phone already has a profile.
  Future<bool> hasProfileForCurrentUser() async =>
      (await getCurrentUserModel()) != null;

  /// Load a user's profile from [collection] by their Firebase Auth UID.
  /// Firebase Authentication is the only source of logins: profiles are never
  /// looked up or copied by email, so one Auth account = one profile.
  Future<UserModel?> _fetchUserFromCollection({
    required String collection,
    required String uid,
  }) async {
    try {
      final docSnap = await _db.collection(collection).doc(uid).get();
      if (docSnap.exists && docSnap.data() != null) {
        return UserModel.fromMap(docSnap.data()!, uid);
      }
    } catch (_) {}
    return null;
  }

  /// Agencies are added by the admin (with an email, for which a login is
  /// created), so their doc id is not the login's UID: find the agency by the
  /// login (ownerUid) or by its email. Returns the agency with its doc id as
  /// uid (the id physios, duties and visits refer to).
  Future<UserModel?> _fetchAgency({
    required String uid,
    required String email,
  }) async {
    final byUid = await _fetchUserFromCollection(collection: 'agencies', uid: uid);
    if (byUid != null) return byUid;
    try {
      final owned = await _db
          .collection('agencies')
          .where('ownerUid', isEqualTo: uid)
          .limit(1)
          .get();
      if (owned.docs.isNotEmpty) {
        final doc = owned.docs.first;
        return UserModel.fromMap({...doc.data(), 'role': 'agency'}, doc.id);
      }
      final mail = email.trim().toLowerCase();
      if (mail.isEmpty) return null;
      final snap = await _db
          .collection('agencies')
          .where('email', isEqualTo: mail)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      // remember who logs in for this agency
      await doc.reference.set({'ownerUid': uid}, SetOptions(merge: true));
      return UserModel.fromMap({...doc.data(), 'role': 'agency'}, doc.id);
    } catch (_) {}
    return null;
  }

  /// Register Doctor - Stores data in 'doctors' collection (and 'users' collection)
  Future<UserModel> registerDoctor({
    required String name,
    required String category,
    required String hospital,
    required String mobileNumber,
    String? hospitalArea,
    String? hospitalAddress,
  }) async {
    final uid = _requireVerifiedUid();
    final area = (hospitalArea != null && hospitalArea.isNotEmpty) ? hospitalArea.trim() : 'Wakad';

    final doctorUser = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'doctor',
      name: name.trim(),
      category: category.trim(),
      hospital: hospital.trim(),
      homeAddress: hospitalAddress?.trim() ?? hospital.trim(),
      mobileNumber: mobileNumber.trim(),
      city: area,
      preferredLocations: [area],
    );

    final doctorMap = doctorUser.toMap();

    await _db.collection('doctors').doc(uid).set(doctorMap);
    await FirestoreService.saveAccountRecord(doctorMap, uid);

    return doctorUser;
  }

  /// Register Patient - Stores data in 'patients' collection (and 'users' collection)
  Future<UserModel> registerPatient({
    required String name,
    required String phone,
    required String age,
  }) async {
    final uid = _requireVerifiedUid();
    final patientUser = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'patient',
      name: name.trim(),
      phone: phone.trim(),
      age: age.trim(),
    );

    final patientMap = patientUser.toMap();

    await _db.collection('patients').doc(uid).set(patientMap);
    await FirestoreService.saveAccountRecord(patientMap, uid);

    return patientUser;
  }

  /// Register Technician
  Future<UserModel> registerTechnician({
    required String name,
    required String phone,
    required String qualification,
    required String organisation,
    required String experience,
    required String city,
  }) async {
    final uid = _requireVerifiedUid();
    final techUser = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'technician',
      name: name.trim(),
      phone: phone.trim(),
      mobileNumber: phone.trim(),
      qualification: qualification.trim(),
      organisation: organisation.trim(),
      experience: experience.trim(),
      city: city.trim(),
    );

    final techMap = techUser.toMap();

    await _db.collection('technicians').doc(uid).set(techMap);
    await FirestoreService.saveAccountRecord(techMap, uid);

    return techUser;
  }

  /// Register Nurse
  Future<UserModel> registerNurse({
    required String name,
    required String phone,
    required String qualification,
    required String organisation,
    required String experience,
    required String city,
  }) async {
    final uid = _requireVerifiedUid();
    final nurseUser = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'nurse',
      name: name.trim(),
      phone: phone.trim(),
      mobileNumber: phone.trim(),
      qualification: qualification.trim(),
      organisation: organisation.trim(),
      experience: experience.trim(),
      city: city.trim(),
    );

    final nurseMap = nurseUser.toMap();

    await _db.collection('nurses').doc(uid).set(nurseMap);
    await FirestoreService.saveAccountRecord(nurseMap, uid);

    return nurseUser;
  }

  /// Register Therapist
  Future<UserModel> registerTherapist({
    required String name,
    required String phone,
    required String qualification,
    required String organisation,
    required String experience,
    required String city,
    String? degreeCertUrl,
  }) async {
    final uid = _requireVerifiedUid();
    final therapistUser = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'therapist',
      name: name.trim(),
      phone: phone.trim(),
      mobileNumber: phone.trim(),
      qualification: qualification.trim(),
      organisation: organisation.trim(),
      experience: experience.trim(),
      city: city.trim(),
      degreeCertUrl: degreeCertUrl?.trim(),
      isVerified: false,
    );

    final therapistMap = therapistUser.toMap();

    await _db.collection('therapists').doc(uid).set(therapistMap);
    await FirestoreService.saveAccountRecord(therapistMap, uid);

    return therapistUser;
  }

  /// Register Care Physician: a doctor who claims per-shift hospital duties
  /// and applies for full-time RMO jobs. The rest of the profile (procedures,
  /// duty types, areas, hospitals) is filled in the profile wizard.
  Future<UserModel> registerCarePhysician({
    required String firstName,
    required String lastName,
    required String phone,
    required String qualification,
    required String regNo,
    required int experienceYears,
  }) async {
    final uid = _requireVerifiedUid();
    final regError = Validators.medicalRegistration(regNo);
    if (regError != null) throw Exception(regError);
    if (await CarePhysicianService.regNoTaken(regNo, uid)) {
      throw Exception(
          'This medical registration number is already registered with another account.');
    }
    final name = '${firstName.trim()} ${lastName.trim()}'.trim();
    final user = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'care_physician',
      name: name,
      phone: phone.trim(),
      mobileNumber: phone.trim(),
      qualification: qualification,
      experience: '$experienceYears',
      isVerified: false,
    );
    final map = {
      ...user.toMap(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'regNo': regNo.trim(),
      'regNoKey': Validators.registrationKey(regNo),
      'experienceYears': experienceYears,
      'available': true,
      'procedures': <String>[],
      'dutyTypes': <String>[],
      'ageGroups': <String>[],
      'specialties': <String>[],
      'areas': <String>[],
      'preferredHospitals': <String>[],
      'noShows': 0,
      'createdAt': IstClock.now().toIso8601String(),
    };
    await _db.collection('care_physicians').doc(uid).set(map);
    await FirestoreService.saveAccountRecord(map, uid);
    return user;
  }

  /// Register Hospital (Email, Password, Hospital Name, Location/City, Phone)
  Future<UserModel> registerHospital({
    required String hospitalName,
    required String city,
    required String phone,
  }) async {
    final uid = _requireVerifiedUid();
    final hospitalUser = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'hospital',
      name: hospitalName.trim(),
      hospital: hospitalName.trim(),
      city: city.trim(),
      phone: phone.trim(),
      mobileNumber: phone.trim(),
    );

    final hMap = hospitalUser.toMap();

    await _db.collection('hospitals').doc(uid).set(hMap);
    await FirestoreService.saveAccountRecord(hMap, uid);

    return hospitalUser;
  }

  /// Register Ambulance (Email, Password, Driver Name, Vehicle Number, City, Phone)
  Future<UserModel> registerAmbulance({
    required String driverName,
    required String vehicleNumber,
    required String city,
    required String phone,
  }) async {
    final uid = _requireVerifiedUid();
    final ambUser = UserModel(
      uid: uid,
      email: _auth.currentUser?.email ?? '',
      role: 'ambulance',
      name: driverName.trim(),
      vehicleNumber: vehicleNumber.trim(),
      city: city.trim(),
      phone: phone.trim(),
      mobileNumber: phone.trim(),
    );

    final ambMap = ambUser.toMap();

    await _db.collection('ambulances').doc(uid).set(ambMap);
    await FirestoreService.saveAccountRecord(ambMap, uid);

    return ambUser;
  }

  /// Update Patient Profile fields
  Future<UserModel> updatePatientProfile({
    required String uid,
    required String name,
    required String phone,
    required String age,
    required String bloodGroup,
    required String weight,
    required String allergy,
    required String homeAddress,
    required String emergencyContact,
    String? profilePicUrl,
    List<String>? preferredDoctorUids,
    List<String>? preferredDoctorNames,
  }) async {
    final doc = await _db.collection('patients').doc(uid).get();
    final data = doc.data() ?? {};
    final email = data['email'] ?? _auth.currentUser?.email ?? '';
    final existingPic = profilePicUrl ?? data['profilePicUrl'];

    final updatedPatient = UserModel(
      uid: uid,
      email: email,
      role: 'patient',
      name: name.trim(),
      profilePicUrl: existingPic,
      phone: phone.trim(),
      age: age.trim(),
      bloodGroup: bloodGroup.trim(),
      weight: weight.trim(),
      allergy: allergy.trim(),
      homeAddress: homeAddress.trim(),
      emergencyContact: emergencyContact.trim(),
      preferredDoctorUids: preferredDoctorUids,
      preferredDoctorNames: preferredDoctorNames,
    );

    final updatedMap = updatedPatient.toMap();

    await _db.collection('patients').doc(uid).set(updatedMap, SetOptions(merge: true));
    await FirestoreService.saveAccountRecord(updatedMap, uid);

    // the saved profile with everything already there (location, favourites…)
    return UserModel.fromMap({...data, ...updatedMap}, uid);
  }

  /// Update Doctor Profile fields
  Future<UserModel> updateDoctorProfile({
    required String uid,
    required String name,
    required String category,
    required String hospital,
    required String mobileNumber,
    required String experience,
    required String qualification,
    String? profilePicUrl,
  }) async {
    final doc = await _db.collection('doctors').doc(uid).get();
    final data = doc.data() ?? {};
    final email = data['email'] ?? _auth.currentUser?.email ?? '';
    final existingPic = profilePicUrl ?? data['profilePicUrl'];

    final updatedDoctor = UserModel(
      uid: uid,
      email: email,
      role: 'doctor',
      name: name.trim(),
      profilePicUrl: existingPic,
      category: category.trim(),
      hospital: hospital.trim(),
      mobileNumber: mobileNumber.trim(),
      experience: experience.trim(),
      qualification: qualification.trim(),
    );

    // Editing profile details must not touch the document approval: the
    // verification status only changes when verification documents change
    // (see verification_service.dart). So `isVerified` is never written here.
    final updatedMap = updatedDoctor.toMap()..remove('isVerified');

    await _db.collection('doctors').doc(uid).set(updatedMap, SetOptions(merge: true));
    await FirestoreService.saveAccountRecord(updatedMap, uid);

    // Return the saved profile with everything that was already there
    // (verification, documents, rating, ...), not a fresh unverified one.
    return UserModel.fromMap({...data, ...updatedMap}, uid);
  }

  /// Update Therapist Profile fields
  Future<UserModel> updateTherapistProfile({
    required String uid,
    required String name,
    required String phone,
    required String qualification,
    required String organisation,
    required String experience,
    required String city,
    String? aadhaarUrl,
    String? degreeCertUrl,
    String? internshipCertUrl,
    String? registrationCertUrl,
    String? profilePicUrl,
  }) async {
    final doc = await _db.collection('therapists').doc(uid).get();
    final data = doc.data() ?? {};
    final email = data['email'] ?? _auth.currentUser?.email ?? '';
    final existingPic = profilePicUrl ?? data['profilePicUrl'];
    final existingAadhaar = aadhaarUrl ?? data['aadhaarUrl'];
    final existingDegree = degreeCertUrl ?? data['degreeCertUrl'];
    final existingInternship = internshipCertUrl ?? data['internshipCertUrl'];
    final existingReg = registrationCertUrl ?? data['registrationCertUrl'];

    final updatedTherapist = UserModel(
      uid: uid,
      email: email,
      role: 'therapist',
      name: name.trim(),
      profilePicUrl: existingPic,
      phone: phone.trim(),
      mobileNumber: phone.trim(),
      qualification: qualification.trim(),
      organisation: organisation.trim(),
      experience: experience.trim(),
      city: city.trim(),
      aadhaarUrl: existingAadhaar,
      degreeCertUrl: existingDegree,
      internshipCertUrl: existingInternship,
      registrationCertUrl: existingReg,
      isVerified: data['isVerified'] ?? false,
    );

    final updatedMap = updatedTherapist.toMap();

    await _db.collection('therapists').doc(uid).set(updatedMap, SetOptions(merge: true));
    await FirestoreService.saveAccountRecord(updatedMap, uid);

    return updatedTherapist;
  }

  /// Logs in with email and password and loads the profile for the role
  /// chosen on the login screen.
  ///
  /// Only one device can be signed in at a time and nobody is signed out
  /// behind their back: if the account is active on another device this
  /// throws [SessionConflictException] (nothing is changed). The login screen
  /// asks the user and, if they agree, calls again with [takeOver] = true.
  Future<UserModel> loginWithEmail({
    required String email,
    required String password,
    String? expectedRole,
    bool takeOver = false,
  }) async {
    ExperimentEnvironment.requireExternalActions();
    var conflict = false;
    // The device is about to sign in: don't let the old session id of this
    // account (from another device) sign it out before login completes.
    SessionService.pause();
    try {
      final cleanEmail = email.trim().toLowerCase();
      try {
        await _auth.signInWithEmailAndPassword(
            email: cleanEmail, password: password);
      } on FirebaseAuthException catch (e) {
        // an account is never created here: logging in must not grant a role
        throw Exception(handleAuthException(e));
      }
      final user = await _loadProfileForLogin(expectedRole: expectedRole);
      if (!takeOver) {
        final remote = await SessionService.remoteSession(user.uid);
        final local = await SessionService.localId(user.uid);
        if (remote.id.isNotEmpty && remote.id != local) {
          conflict = true;
          // keep the check paused while the user decides
          SessionService.pause(const Duration(minutes: 10));
          throw SessionConflictException(remote.device, remote.at);
        }
      }
      // This device is now the only active session; a device the user chose
      // to replace is signed out the next time it syncs.
      await SessionService.claim(user.uid);
      return user;
    } finally {
      if (!conflict) SessionService.resume();
    }
  }

  Future<UserModel> _loadProfileForLogin({String? expectedRole}) async {
    final current = _auth.currentUser;
    if (current == null) {
      throw Exception('Please log in first.');
    }
    final cleanEmail = (current.email ?? '').toLowerCase();
    final uid = current.uid;

    final cleanRole = (expectedRole ?? '').toLowerCase();

    // Admin access is limited to the configured admin email.
    final bool isAdminEmail = adminEmail.isNotEmpty && cleanEmail == adminEmail;
    if (cleanRole == 'admin' || isAdminEmail) {
      if (!isAdminEmail) {
        await _auth.signOut();
        throw Exception(
            'Access Denied: only the authorized administrator can access the Admin Portal.');
      }
      // The admin account only signs in from the Admin tab
      if (cleanRole.isNotEmpty && cleanRole != 'admin') {
        await _auth.signOut();
        throw Exception(
            'This is the admin account. Select "Admin" above to log in.');
      }

      // Only a pre-provisioned role record for this authenticated UID can
      // authorize admin login. Signing in must never grant roles itself.
      final userDoc = await _db.collection('users').doc(uid).get();
      final data = userDoc.data();
      if (!canUseProvisionedAdminPortal(
        authenticatedEmail: cleanEmail,
        configuredAdminEmail: adminEmail,
        storedRole: data?['role'],
      )) {
        await _auth.signOut();
        throw Exception(
            'Administrator access is not provisioned for this account. Contact your system administrator.');
      }
      return UserModel.fromMap(data!, uid);
    }

    // The account must belong to the role selected on the login screen.
    // A nurse's email/password entered on the Tech tab must not log in.
    final selectedCollection = _roleCollections[cleanRole];
    if (selectedCollection != null) {
      final user = cleanRole == 'agency'
          ? await _fetchAgency(uid: uid, email: cleanEmail)
          : await _fetchUserFromCollection(
              collection: selectedCollection, uid: uid);
      if (user != null) {
        await _recordAccountRole(user, uid);
        return user;
      }

      // Wrong tab: find the real role only to say which tab to use
      String? actualRole;
      for (final entry in _roleCollections.entries) {
        if (entry.key == cleanRole) continue;
        final other =
            await _fetchUserFromCollection(collection: entry.value, uid: uid);
        if (other != null) {
          actualRole = entry.key;
          break;
        }
      }
      await _auth.signOut();
      final selected = _roleLabels[cleanRole] ?? cleanRole;
      if (actualRole != null) {
        final actual = _roleLabels[actualRole] ?? actualRole;
        throw Exception(
            'This account is registered as $actual, not $selected. '
            'Select "$actual" above to log in.');
      }
      throw Exception(
          'No $selected account found for $cleanEmail. '
          'Check the selected role or tap "Register Now".');
    }

    // No role selected: use whichever role profile the account has
    for (final col in [..._roleCollections.values, 'users']) {
      final user = await _fetchUserFromCollection(collection: col, uid: uid);
      if (user != null) return user;
    }

    await _auth.signOut();
    throw Exception('User record not found in database.');
  }

  /// Makes sure users/{uid} has the account's role (older accounts were
  /// created without it), so later startups open the right profile directly.
  Future<void> _recordAccountRole(UserModel user, String uid) async {
    if (user.role.isEmpty || user.isAdmin) return;
    try {
      await FirestoreService.saveAccountRecord(user.toMap(), uid);
    } catch (_) {
      // Not critical: startup falls back to checking each role collection
    }
  }

  /// Login tab role → Firestore collection holding that role's profiles.
  static const Map<String, String> _roleCollections = {
    'patient': 'patients',
    'doctor': 'doctors',
    'hospital': 'hospitals',
    'ambulance': 'ambulances',
    'technician': 'technicians',
    'therapist': 'therapists',
    'nurse': 'nurses',
    'agency': 'agencies',
    'care_physician': 'care_physicians',
  };

  /// Names as shown on the login role tabs.
  static const Map<String, String> _roleLabels = {
    'patient': 'Patient',
    'doctor': 'Doctor',
    'hospital': 'Hospital',
    'ambulance': 'Ambulance',
    'technician': 'Tech',
    'therapist': 'Therapist',
    'nurse': 'Nurse',
    'agency': 'Agency',
    'care_physician': 'Care Physician',
  };

  /// Get Current User Model by checking all collections
  Future<UserModel?> getCurrentUserModel() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final uid = user.uid;

    // users/{uid} holds the account's role: open that profile directly
    try {
      final account = await _db.collection('users').doc(uid).get();
      final role = (account.data()?['role'] ?? '').toString();
      if (role == 'admin') {
        return UserModel.fromMap(account.data()!, uid);
      }
      final collection = _roleCollections[role];
      if (collection != null) {
        final model = role == 'agency'
            ? await _fetchAgency(uid: uid, email: user.email ?? '')
            : await _fetchUserFromCollection(collection: collection, uid: uid);
        if (model != null) return model;
      }
    } catch (_) {}

    // Older accounts without a role record: look in each role collection
    for (final col in [..._roleCollections.values, 'users']) {
      final model = await _fetchUserFromCollection(collection: col, uid: uid);
      if (model != null) {
        await _recordAccountRole(model, uid);
        return model;
      }
    }

    return null;
  }

  // ------------------------------------------------- deleting the account
  // Like Facebook / Instagram (functions/delete_account.js): the account is
  // deactivated now and deleted for good after 30 days, unless the user
  // logs in again and keeps it.

  /// How long a deactivated account can still be kept.
  static const int deletionGraceDays = 30;

  /// Deactivates the account, schedules its deletion and signs out. Returns
  /// the day it will be deleted (India time).
  Future<DateTime> requestAccountDeletion() async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('requestAccountDeletion')
        .call();
    final data = res.data;
    final at = IstClock.tryParse(
            (data is Map ? data['deleteAfter'] : null)?.toString() ?? '') ??
        IstClock.now().add(const Duration(days: deletionGraceDays));
    await signOut();
    return at;
  }

  /// "Keep my account": everything is restored as it was.
  Future<void> cancelAccountDeletion() =>
      FirebaseFunctions.instance.httpsCallable('cancelAccountDeletion').call();

  /// When the signed-in account will be deleted (India time), or null if it
  /// is not scheduled for deletion.
  Future<DateTime?> scheduledDeletion() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final d = (await _db.collection('users').doc(uid).get()).data()?['deletion'];
    if (d is! Map) return null;
    return IstClock.tryParse((d['deleteAfter'] ?? '').toString());
  }

  /// Sign out
  Future<void> signOut() async {
    // stop sharing live location (on-duty doctors / ambulances)
    await LocationTracker.stop();
    // stop pushes for this account on this device
    final uid = _auth.currentUser?.uid;
    if (uid != null) await PushService.unregisterForUser(uid);
    // free the account for the next login (the session guard stays paused so
    // it doesn't claim the account again while we sign out)
    SessionService.pause(const Duration(seconds: 30));
    if (uid != null) await SessionService.release(uid);
    await SessionService.clearLocal(uid);
    await _auth.signOut();
    SessionService.resume();
  }
}
