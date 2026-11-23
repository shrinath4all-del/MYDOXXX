import '../../services/app_database.dart';
import 'dart:async';
import '../../widgets/delete_account_button.dart';
import '../../utils/form_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/push_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import 'care/control_room_screen.dart';
import 'nurse/nurse_control_room_screen.dart';
import 'technician/technician_control_room_screen.dart';
import 'physio/physio_control_room_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/validators.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../utils/ist_clock.dart';
import '../../widgets/app_alert_dialog.dart';

class AgencyHomeScreen extends StatefulWidget {
  final UserModel agency;

  const AgencyHomeScreen({
    super.key,
    required this.agency,
  });

  @override
  State<AgencyHomeScreen> createState() => _AgencyHomeScreenState();
}

class _AgencyHomeScreenState extends State<AgencyHomeScreen> {
  final AuthService _authService = AuthService();
  late UserModel _agency;
  StreamSubscription? _profileSub;
  // Agency profile; agencyType decides physio team view or Control Room
  Map<String, dynamic>? _raw;

  // Why the profile could not be shown (instead of loading forever)
  Object? _loadError;
  bool _missing = false;
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    PushService.registerForUser(widget.agency.uid);
    _agency = widget.agency;
    _listen();
  }

  void _listen() {
    _profileSub?.cancel();
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _raw == null) setState(() => _slow = true);
    });
    _profileSub =
        FirestoreServiceLive.getUserStream(_agency.uid, 'agencies').listen(
      (doc) {
        if (!mounted) return;
        final data = doc.data();
        if (!doc.exists || data == null) {
          setState(() => _missing = true);
          return;
        }
        UserModel? parsed;
        try {
          parsed = UserModel.fromMap(data, _agency.uid);
        } catch (_) {
          // keep the login copy; the Control Room only needs the raw data
        }
        setState(() {
          _raw = data;
          _missing = false;
          _loadError = null;
          if (parsed != null) _agency = parsed;
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _loadError = e);
      },
    );
  }

  void _retry() {
    setState(() {
      _loadError = null;
      _missing = false;
      _slow = false;
    });
    _listen();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _editAgencySettings() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: _agency.name);
    final cityCtrl = TextEditingController(text: _agency.city ?? '');
    final phoneCtrl = TextEditingController(text: _agency.phone ?? _agency.mobileNumber ?? '');
    // The dialog is closed before the message shows: use the screen's
    // messenger, not the dialog's context
    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: const Text('Edit Agency Profile'),
        content: SizedBox(
          width: Responsive.dialogWidth(context),
          child: Form(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    validator: (v) => Validators.orgName(v, label: 'agency name'),
                    decoration: const InputDecoration(labelText: 'Agency Name'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: cityCtrl,
                    validator: Validators.city,
                    decoration: const InputDecoration(labelText: 'City / Primary Area'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    // the login number: only the admin changes it
                    enabled: false,
                    decoration: const InputDecoration(
                        labelText: 'Mobile number (set by admin)'),
                  ),
                  const SizedBox(height: 8),
                  const DeleteAccountButton(),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () async {
              if (!FormUtils.validate(formKey)) return;
              try {
                await AppDatabase.instance
                    .collection('agencies')
                    .doc(_agency.uid)
                    .set({
                  'name': nameCtrl.text.trim(),
                  'organisation': nameCtrl.text.trim(),
                  'city': cityCtrl.text.trim(),
                  'updatedAt': IstClock.now().toIso8601String(),
                }, SetOptions(merge: true));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Agency profile updated successfully.')),
                );
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                  content: Text(ErrorMessages.of(e, action: 'update agency')),
                  backgroundColor: AppColors.danger,
                ));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_raw == null) {
      final String? message = _loadError != null
          ? ErrorMessages.of(_loadError!, action: 'load your agency')
          : _missing
              ? 'No agency profile was found for this account. '
                  'Log out and register as an agency, or log in with the '
                  'agency\'s mobile number.'
              : _slow
                  ? 'This is taking longer than usual. Check your internet '
                      'connection and try again.'
                  : null;
      return Scaffold(
        appBar: AppBar(
          title: Text(_agency.name.isNotEmpty ? _agency.name : 'Agency'),
          actions: [
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _logout,
            ),
          ],
        ),
        body: Center(
          child: message == null
              ? const CircularProgressIndicator(color: AppTheme.primaryTeal)
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          size: 48, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(120, 44)),
                              onPressed: _retry, child: const Text('Retry')),
                          OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(120, 44)),
                              onPressed: _logout,
                              child: const Text('Log out')),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    // Care physician agency: duties, attendance and money (older agency
    // accounts without a type registered as physio agencies)
    if (_raw!['agencyType'] == 'care_physician') {
      return AgencyControlRoomScreen(agencyId: _agency.uid);
    }
    // Nurse agency: nurses, hospital requests, duties and earnings
    if (_raw!['agencyType'] == 'nurse') {
      return NurseAgencyControlRoomScreen(agencyId: _agency.uid);
    }
    // Technician partner: technicians, hospital requests, duties, earnings
    if (_raw!['agencyType'] == 'technician') {
      return TechnicianAgencyControlRoomScreen(agencyId: _agency.uid);
    }
    // Physio agency: same Control Room layout, for the physio team
    return PhysioControlRoomScreen(
      agencyId: _agency.uid,
      onEditProfile: _editAgencySettings,
      onLogout: _logout,
    );
  }
}

class FirestoreServiceLive {
  static Stream<DocumentSnapshot<Map<String, dynamic>>> getUserStream(
      String uid, String collection) {
    return AppDatabase.instance.collection(collection).doc(uid).snapshots();
  }
}
