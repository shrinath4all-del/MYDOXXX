import '../../services/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/care_duty_rate_service.dart';
import '../../services/payment_service.dart';
import '../../theme/app_theme.dart';
import '../../services/verification_service.dart';
import '../../widgets/admin_verification_review_dialog.dart';
import '../auth/login_screen.dart';
import 'care_earnings_screen.dart';
import 'physio_agencies_panel.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../services/firestore_service.dart';
import 'care_physicians_panel.dart';
import 'freelancers_panel.dart';
import '../../widgets/document_viewer_screen.dart';
import '../shifts/shift_board_screen.dart';
import '../../constants/app_colors.dart';

class AdminHomeScreen extends StatefulWidget {
  final UserModel admin;

  const AdminHomeScreen({
    super.key,
    required this.admin,
  });

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  final AuthService _authService = AuthService();
  int _selectedRoleTab =
      0; // 0 = Doctors, 1 = Hospitals, 2 = Ambulances, 3 = Technicians, 4 = Nurses, 5 = Therapists, 6 = Physio agencies
  static const int _agenciesTab = 6;
  static const int _carePhysiciansTab = 7;
  static const int _shiftsTab = 8;
  static const int _freelancersTab = 9;
  int _selectedFilterStatus = 0; // 0 = Pending Approval, 1 = Verified

  void _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }


  String get _selectedRoleName => _selectedRoleTab == 0
      ? 'doctor'
      : (_selectedRoleTab == 1
          ? 'hospital'
          : (_selectedRoleTab == 2
              ? 'ambulance'
              : (_selectedRoleTab == 3
                  ? 'technician'
                  : (_selectedRoleTab == 4 ? 'nurse' : 'therapist'))));

  /// Per-document review (role-specific list from Firestore
  /// 'verification_requirements'), with provider approval gated on all
  /// mandatory documents being approved.
  void _showDocumentPreviewDialog(Map<String, dynamic> providerData) {
    showDialog(
      context: context,
      builder: (_) => AdminVerificationReviewDialog(
        role: _selectedRoleName,
        uid: (providerData['uid'] ?? '').toString(),
        providerName: (providerData['name'] ?? 'Provider').toString(),
        onViewFile: (title, url) =>
            DocumentViewerScreen.open(context, url: url, title: title),
      ),
    );
  }

  /// The admin picks a hospital's category; the price list of each is shown.
  Future<String?> _askHospitalCategory(String uid, {String? current}) async {
    final existing = current ??
        (await AppDatabase.instance.collection('hospitals').doc(uid).get())
            .data()?['rateCategory']
            ?.toString();
    String chosen = HospitalCategory.normalize(existing);
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Hospital category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'The category decides what this hospital pays for a duty. Only the admin can change it.',
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final c in HospitalCategory.all)
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: c,
                  groupValue: chosen,
                  onChanged: (v) => setLocal(() => chosen = v ?? chosen),
                  title: Text(HospitalCategory.label(c)),
                  subtitle: Text(
                      'ICU ₹${HospitalCategory.rateFor(c, 'icu')} · Ward ₹${HospitalCategory.rateFor(c, 'ward')} · Casualty ₹${HospitalCategory.rateFor(c, 'casualty')} · Pediatric ward ₹${HospitalCategory.rateFor(c, 'specialty')}',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, chosen),
                child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  Future<void> _changeHospitalCategory(String uid, String? current) async {
    final messenger = ScaffoldMessenger.of(context);
    final c = await _askHospitalCategory(uid, current: current);
    if (c == null) return;
    await CareDutyRates.setCategory(uid, c);
    messenger.showSnackBar(SnackBar(
      content: Text('Category set to ${HospitalCategory.label(c)}.'),
      backgroundColor: AppColors.successDark,
    ));
  }

  /// CareConnect rule: a profile stays non-bookable until every mandatory
  /// role-specific document is reviewed and approved by the admin.
  void _toggleVerificationStatus({
    required String uid,
    required String role,
    required bool currentStatus,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    if (currentStatus) {
      await VerificationService.revokeProvider(role: role, uid: uid);
      messenger.showSnackBar(SnackBar(
        content: const Text('Verification revoked. Profile is not bookable.'),
        backgroundColor: AppColors.orange,
      ));
      return;
    }

    // a hospital is put in a category (small, medium, high) when it is
    // verified: it decides what its duties cost
    String? category;
    if (role == 'hospital') {
      category = await _askHospitalCategory(uid);
      if (category == null) return; // cancelled
    }

    final blocking =
        await VerificationService.approveProvider(role: role, uid: uid);
    if (category != null && blocking.isEmpty) {
      await CareDutyRates.setCategory(uid, category);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(blocking.isEmpty
          ? 'Provider approved. Profile is now bookable.'
          : 'Cannot approve yet. Review these documents first: ${blocking.join(', ')}'),
      backgroundColor:
          blocking.isEmpty ? AppColors.successDark : AppColors.orange,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final String collectionName = _selectedRoleTab == 0
        ? 'doctors'
        : (_selectedRoleTab == 1
            ? 'hospitals'
            : (_selectedRoleTab == 2
                ? 'ambulances'
                : (_selectedRoleTab == 3
                    ? 'technicians'
                    : (_selectedRoleTab == 4 ? 'nurses' : 'therapists'))));

    final String roleName = _selectedRoleTab == 0
        ? 'doctor'
        : (_selectedRoleTab == 1
            ? 'hospital'
            : (_selectedRoleTab == 2
                ? 'ambulance'
                : (_selectedRoleTab == 3
                    ? 'technician'
                    : (_selectedRoleTab == 4 ? 'nurse' : 'therapist'))));

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('Main Admin Portal'),
        actions: [
          IconButton(
            tooltip: 'MyDox earnings',
            icon: const Icon(Icons.currency_rupee_rounded, color: AppColors.muted),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminEarningsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.muted),
            onPressed: _signOut,
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Admin Banner Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryTeal,
                    child: Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.white, size: 26),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Healthcare Verification Desk',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Review Bombay Nursing Cert, Aadhaar, PAN, & Medical Certificates.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Role Selector Bar (Doctors vs Hospitals vs Ambulances vs Technicians vs Nurses)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.lineStrong),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildRoleTab(0, 'Doctors'),
                    const SizedBox(width: 4),
                    _buildRoleTab(1, 'Hospitals'),
                    const SizedBox(width: 4),
                    _buildRoleTab(2, 'Ambulances'),
                    const SizedBox(width: 4),
                    _buildRoleTab(3, 'Technicians'),
                    const SizedBox(width: 4),
                    _buildRoleTab(4, 'Nurses'),
                    const SizedBox(width: 4),
                    _buildRoleTab(5, 'Therapists'),
                    const SizedBox(width: 4),
                    _buildRoleTab(_agenciesTab, 'Agencies'),
                    const SizedBox(width: 4),
                    _buildRoleTab(_carePhysiciansTab, 'Care Physicians'),
                    const SizedBox(width: 4),
                    _buildRoleTab(_shiftsTab, 'Shifts & Jobs'),
                    const SizedBox(width: 4),
                    _buildRoleTab(_freelancersTab, 'Freelancers'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Status Filter Chips (Pending vs Verified)
            if (_selectedRoleTab != _agenciesTab &&
                _selectedRoleTab != _freelancersTab)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Pending Approval'),
                      selected: _selectedFilterStatus == 0,
                      selectedColor: AppColors.warningSoft,
                      labelStyle: TextStyle(
                        color: _selectedFilterStatus == 0
                            ? AppColors.warningDeep
                            : AppTheme.darkNavy,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedFilterStatus = 0);
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: const Text('Verified Providers'),
                      selected: _selectedFilterStatus == 1,
                      selectedColor: AppColors.successSoft,
                      labelStyle: TextStyle(
                        color: _selectedFilterStatus == 1
                            ? AppColors.successDeep
                            : AppTheme.darkNavy,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedFilterStatus = 1);
                      },
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            if (_selectedRoleTab == _agenciesTab)
              const Expanded(child: PhysioAgenciesPanel())
            else if (_selectedRoleTab == _carePhysiciansTab)
              const Expanded(child: CarePhysiciansPanel())
            else if (_selectedRoleTab == _freelancersTab)
              const Expanded(child: FreelancersPanel())
            else if (_selectedRoleTab == _shiftsTab)
              Expanded(
                child: ShiftBoardScreen(
                  postedBy: 'admin',
                  posterId: 'admin',
                  posterName: 'MedConnect',
                  hospitals: FirestoreService.hospitalsListStream().map((list) => [
                        for (final h in list)
                          (
                            id: h['uid'].toString(),
                            name: (h['name'] ?? h['hospital'] ?? '').toString(),
                            area: ((h['preferredLocations'] as List?)?.isNotEmpty ??
                                    false)
                                ? (h['preferredLocations'] as List).first.toString()
                                : (h['city'] ?? '').toString(),
                          )
                      ]),
                ),
              )
            else
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _streams.get(
                      'providers:$collectionName',
                      () => AppDatabase.instance
                          .collection(collectionName)
                          .snapshots()),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return LoadErrorView(
                          error: snapshot.error, what: 'providers');
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primaryTeal),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final List<Map<String, dynamic>> filteredList = [];

                    for (var doc in docs) {
                      final data = doc.data();
                      data['uid'] = doc.id;
                      final bool isVerified = data['isVerified'] == true;

                      if (_selectedFilterStatus == 0 && !isVerified) {
                        filteredList.add(data);
                      } else if (_selectedFilterStatus == 1 && isVerified) {
                        filteredList.add(data);
                      }
                    }

                    if (filteredList.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _selectedFilterStatus == 0
                                  ? Icons.verified_user_outlined
                                  : Icons.people_outline_rounded,
                              size: 54,
                              color: AppColors.lineStrong,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedFilterStatus == 0
                                  ? 'No Pending Approval Requests'
                                  : 'No Verified Providers in this category',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final item = filteredList[index];
                        final uid = item['uid'] ?? '';
                        final name = item['name'] ?? 'Provider';
                        final phone =
                            item['phone'] ?? item['mobileNumber'] ?? '';
                        final qual = item['qualification'] ??
                            item['category'] ??
                            item['vehicleNumber'] ??
                            '';
                        final org = item['organisation'] ??
                            item['hospital'] ??
                            item['city'] ??
                            '';
                        final bool isVerified = item['isVerified'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: isVerified
                                    ? AppColors.successLight
                                    : AppColors.warningBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: isVerified
                                        ? AppColors.successTint
                                        : AppColors.orangeTint,
                                    child: Icon(
                                      isVerified
                                          ? Icons.verified_rounded
                                          : Icons.pending_actions_rounded,
                                      color: isVerified
                                          ? AppColors.successDark
                                          : AppColors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: AppTheme.darkNavy,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$qual • $org',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textMuted),
                                        ),
                                        // Bank account for online payments
                                        if (const {
                                          'doctor',
                                          'technician',
                                          'nurse',
                                          'therapist'
                                        }.contains(roleName))
                                          Text(
                                            PaymentService.payoutStatusLabel(
                                                item),
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: PaymentService
                                                        .payoutsActive(item)
                                                    ? AppColors.successDark
                                                    : AppColors.orange),
                                          ),
                                        if (roleName == 'hospital')
                                          Text(
                                            'Category: ${HospitalCategory.label(HospitalCategory.normalize(item['rateCategory']))}'
                                            '${(item['rateCategory'] ?? '').toString().isEmpty ? ' (not set)' : ''}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.darkNavy),
                                          ),
                                        if (phone.isNotEmpty)
                                          Text(
                                            'Phone: $phone',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.primaryTeal,
                                                fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isVerified
                                          ? AppColors.successTint
                                          : AppColors.orangeTint,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      isVerified ? 'VERIFIED' : 'PENDING',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isVerified
                                            ? AppColors.successDeep
                                            : AppColors.warningDeep,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _showDocumentPreviewDialog(item),
                                      icon: const Icon(
                                          Icons.folder_shared_outlined,
                                          size: 16),
                                      label: const Text('View Documents'),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 40),
                                      ),
                                    ),
                                  ),
                                  if (roleName == 'hospital') ...[
                                    const SizedBox(width: 10),
                                    OutlinedButton(
                                      onPressed: () => _changeHospitalCategory(
                                          uid, item['rateCategory']?.toString()),
                                      style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 40)),
                                      child: const Text('Category'),
                                    ),
                                  ],
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    onPressed: () => _toggleVerificationStatus(
                                      uid: uid,
                                      role: roleName,
                                      currentStatus: isVerified,
                                    ),
                                    icon: Icon(
                                      isVerified
                                          ? Icons.close_rounded
                                          : Icons.check_circle_rounded,
                                      size: 16,
                                    ),
                                    label:
                                        Text(isVerified ? 'Revoke' : 'Approve'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isVerified
                                          ? AppColors.danger
                                          : AppColors.successDark,
                                      minimumSize: const Size(100, 40),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleTab(int index, String label) {
    final isSelected = _selectedRoleTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedRoleTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppTheme.darkNavy,
          ),
        ),
      ),
    );
  }
}

