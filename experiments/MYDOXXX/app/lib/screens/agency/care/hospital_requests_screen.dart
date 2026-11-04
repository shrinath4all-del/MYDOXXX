import '../../../services/app_database.dart';
import 'care_doctor_profile_screen.dart';
import '../../../utils/safe_cast.dart';
import 'package:flutter/material.dart';

import '../../../services/care_agency_service.dart';
import '../../../models/care_duty_roster.dart';
import '../../../services/care_duty_service.dart';
import '../../../services/care_physician_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/responsive.dart';
import '../../../utils/stream_cache.dart';
import '../../../constants/app_colors.dart';

typedef _Cp = CarePhysicianService;

/// Care physician requests that hospitals posted. This is the only kind of
/// request a partner agency sees: a patient's home-care booking never shows
/// here. The agency assigns one of its own care physicians to a request.
class HospitalRequestsScreen extends StatefulWidget {
  final Map<String, dynamic> agency;
  const HospitalRequestsScreen({super.key, required this.agency});

  @override
  State<HospitalRequestsScreen> createState() => _HospitalRequestsScreenState();
}

class _HospitalRequestsScreenState extends State<HospitalRequestsScreen> {
  final StreamCache _streams = StreamCache();
  String _filter = 'team'; // team | open | mine | approval

  String get _agencyId => (widget.agency['id'] ?? widget.agency['uid'] ?? '').toString();

  /// Open requests in the agency's areas (no areas = any) and the requests
  /// this agency already took.
  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> all) {
    final now = DateTime.now();
    return [
      for (final r in all)
        if (r['postedBy'] == 'hospital' &&
            (_filter == 'approval'
                ? (r['status'] == 'pending_agency' &&
                    (r['pendingAgencyId'] ?? '').toString() == _agencyId)
                : _filter == 'open'
                ? (r['status'] == 'open' &&
                    (_Cp.shiftStart(r)?.isAfter(now) ?? false))
                : (r['claimedAgencyId'] ?? '').toString() == _agencyId))
          r
    ];
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  // One approve / decline / assign at a time: a second tap while the first
  // is still saving would send it twice.
  bool _actionInFlight = false;

  Future<void> _decide(Map<String, dynamic> request,
      {required bool approve}) async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    try {
      if (approve) {
        await _Cp.approveRequest(request, _agencyId);
        _snack('Approved. ${request['claimedByName']} is allocated to the hospital.');
      } else {
        await _Cp.declineRequest(request, _agencyId);
        _snack('Declined. The request is open for other care physicians again.');
      }
    } catch (e) {
      _snack(ErrorMessages.of(e, action: approve ? 'approve the request' : 'decline the request'),
          error: true);
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _assign(Map<String, dynamic> request) async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    try {
      await _assignOnce(request);
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _assignOnce(Map<String, dynamic> request) async {
    final doctor = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PickDoctorSheet(agencyId: _agencyId),
    );
    if (doctor == null) return;
    try {
      final uid = doctor['userUid'].toString();
      final profile =
          (await AppDatabase.instance.collection(_Cp.collection).doc(uid).get())
                  .data() ??
              const <String, dynamic>{};
      await _Cp.claimShift(
        request['id'].toString(),
        {...profile, 'uid': uid, 'name': profile['name'] ?? doctor['name']},
        viaAgencyId: _agencyId,
      );
      _snack('${doctor['name']} is assigned. It is now a duty in your Control Room.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'assign the doctor'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        appBar: AppBar(
          title: const Text('Hospital requests'),
          elevation: 0,
        ),
        body: Column(
          children: [
            // Modern Filter Segment Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('team', 'Team requests', Icons.groups_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip('open', 'Open requests', Icons.explore_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip('approval', 'Approval', Icons.pending_actions_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip('mine', 'Taken by us', Icons.check_circle_rounded),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Expanded(
              child: _filter == 'team'
                  ? _teamList()
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _streams.get('requests', _Cp.hospitalRequestsStream),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return LoadErrorView(error: snap.error, what: 'hospital requests');
                        }
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(color: AppTheme.primaryTeal));
                        }
                        final list = _visible(snap.data!);
                        if (list.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySoft.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _filter == 'approval'
                                          ? Icons.pending_actions_rounded
                                          : _filter == 'open'
                                              ? Icons.explore_off_rounded
                                              : Icons.task_alt_rounded,
                                      size: 48,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _filter == 'approval'
                                        ? 'No requests are waiting for your approval.'
                                        : _filter == 'open'
                                            ? 'No open care physician requests from hospitals right now.'
                                            : 'You have not taken any hospital request yet.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textBody,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (_, i) => _card(list[i]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon) {
    final selected = _filter == key;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _filter = key),
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.line,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.brand.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textBody,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hospitals' team requests: the agency's own doctors who accepted are
  /// shown here and the agency picks who goes.
  Widget _teamList() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('teams', _Cp.hospitalTeamRequestsStream),
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'team requests');
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryTeal));
          }
                final now = DateTime.now();
          final list = [
            for (final r in snap.data!)
              if (r['status'] == 'open' &&
                  (_Cp.shiftStart(r)?.isAfter(now) ?? false))
                r
          ];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.groups_outlined, size: 48, color: AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    const Text('No team requests from hospitals right now.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textBody, fontSize: 15, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) => _TeamCard(
              key: ValueKey(list[i]['id']),
              request: list[i],
              agencyId: _agencyId,
              agencyName: (widget.agency['name'] ?? '').toString(),
              onDone: _snack,
            ),
          );
        },
      );

  Widget _card(Map<String, dynamic> r) {
    final taken = r['status'] == 'claimed' || r['status'] == 'on_duty';
    final isUrgent = r['urgent'] == true;
    final isPendingApproval = r['status'] == 'pending_agency';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUrgent
              ? AppColors.danger.withOpacity(0.5)
              : isPendingApproval
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.line,
          width: isUrgent || isPendingApproval ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isUrgent
                    ? AppColors.danger
                    : isPendingApproval
                        ? AppColors.primary
                        : taken
                            ? AppColors.successDark
                            : AppColors.primaryLight,
                width: 5,
              ),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_hospital_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (r['hospitalName'] ?? 'Hospital').toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 13, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${_Cp.dayLabel(r, DateTime.now())} · ${_Cp.timeRange(r)}'
                                '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
                                style: const TextStyle(fontSize: 13, color: AppColors.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isUrgent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'URGENT',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.line),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Offered Pay', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(
                        '₹${toNum(r['pay'])?.round() ?? 0}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  if (taken && (r['claimedByName'] ?? '').toString().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.successSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.successDark),
                          const SizedBox(width: 6),
                          Text(
                            'Assigned to ${r['claimedByName']}',
                            style: const TextStyle(
                              color: AppColors.successDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (isPendingApproval) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${r['claimedByName'] ?? 'Your doctor'} accepted this request. Approve to allocate.',
                          style: const TextStyle(color: AppColors.primaryDark, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _decide(r, approve: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger, width: 1.5),
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _decide(r, approve: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.successDark,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
              if (!taken && !isPendingApproval) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _assign(r),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Assign a doctor'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The agency's own care physicians that have an app account (only they can
/// be sent to a hospital).
class _PickDoctorSheet extends StatelessWidget {
  final String agencyId;
  const _PickDoctorSheet({required this.agencyId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: CareAgencyService.doctorsStream(agencyId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return Stack(children: [
                  const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator())),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ]);
              }
              final doctors = [
                for (final d in snap.data!)
                  if (d['active'] != false &&
                      (d['userUid'] ?? '').toString().isNotEmpty)
                    d
              ];
              if (doctors.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const Icon(Icons.person_off_outlined, size: 48, color: AppColors.muted),
                      const SizedBox(height: 16),
                      const Text(
                        'None of your care physicians has an app account yet. Add them in Doctors with their mobile number, and ask them to sign in.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textBody, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      const Text('Choose a doctor',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.darkNavy)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.line),
                  const SizedBox(height: 8),
                  for (final d in doctors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: AppColors.page,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => Navigator.pop(context, d),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.primarySoft,
                                  child: const Icon(Icons.person_outline, color: AppColors.primary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((d['name'] ?? '').toString(),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.darkNavy)),
                                      const SizedBox(height: 2),
                                      Text((d['qualification'] ?? '').toString(),
                                          style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}


/// One team request: the agency's doctors who accepted, tick the ones to send.
class _TeamCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final String agencyId;
  final String agencyName;
  final void Function(String msg, {bool error}) onDone;
  const _TeamCard(
      {super.key,
      required this.request,
      required this.agencyId,
      required this.agencyName,
      required this.onDone});

  @override
  State<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends State<_TeamCard> {
  /// A full-time team: the best 10 applicants (any care physician), and the
  /// agency picks who works the Morning, Evening and Night shift.
  Widget _rotationCard() {
    final r = widget.request;
    final top = _Cp.shortlist(r);
    final applied = _Cp.listOf(r['applicantUids']).length;
    final fixed = CareDutyService.fixedShiftOf(r);
    final need = fixed == null ? 3 : 1;
    final shifts = fixed == null ? CareDutyService.teamShifts : [fixed];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.navy, width: 5)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.groups_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((r['hospitalName'] ?? 'Hospital').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppTheme.darkNavy)),
                        const SizedBox(height: 3),
                        Text(
                          '${_Cp.teamKindLabel(r)} from ${r['anchor']}'
                          '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.line),
              ),
              Text('₹${toNum(r['pay'])?.round() ?? 0} per month for each care physician',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
              const SizedBox(height: 12),
              if (top.length < need)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.page,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      applied == 0
                          ? 'No care physician has applied yet.'
                          : 'Only $applied applied so far. You need at least $need to place the ${fixed == null ? 'team' : 'care physician'}.',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                )
              else ...[
                Text(
                    '$applied applied. Choose $need of the best ${top.length} (fewest no-shows, then most experience). The 3 you pick are told they are selected; the others see "Not selected" in their Applied tab:',
                    style: const TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                for (final a in top)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.page,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => CareDoctorProfileScreen.open(context, a.uid,
                              name: (a.data['name'] ?? '').toString()),
                          child: const Icon(Icons.person_rounded, size: 22, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              '${a.data['name'] ?? ''}'
                              ' · ${a.data['experienceYears'] ?? 0} yrs'
                              '${((a.data['noShows'] as num?) ?? 0) > 0 ? ' · ${a.data['noShows']} no-show(s)' : ''}'
                              '${(a.data['agencyName'] ?? '').toString().isEmpty ? ' · freelancer' : ''}'
                              '${(a.data['currentHospital'] ?? '').toString().isEmpty ? '' : ' · moving from ${a.data['currentHospital']}'}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textBody)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Text(fixed == null ? 'Who works which shift?' : 'Who takes the ${fixed.label} shift?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkNavy)),
                const SizedBox(height: 2),
                Text(
                    fixed == null
                        ? 'The rotation then moves each of them to the next shift every week.'
                        : 'They work the ${fixed.label} shift (${_shiftHours(fixed)}) every day.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 10),
                for (final shift in shifts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<String>(
                      value: top.any((a) => a.uid == _byShift[shift]) ? _byShift[shift] : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: '${shift.label} (${_shiftHours(shift)})'),
                      items: [
                        for (final a in top)
                          DropdownMenuItem(
                            value: a.uid,
                            // a physician can only take one shift
                            enabled: _byShift[shift] == a.uid ||
                                !_byShift.values.contains(a.uid),
                            child: Text((a.data['name'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                if (v == null) {
                                  _byShift.remove(shift);
                                } else {
                                  _byShift[shift] = v;
                                }
                              }),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy || _byShift.length != need ? null : _assign,
                    icon: const Icon(Icons.groups_rounded, size: 18),
                    label: Text(_busy
                        ? 'Placing…'
                        : fixed == null
                            ? 'Place the full-time team (${_byShift.length} of 3)'
                            : 'Place the care physician (${_byShift.length} of 1)'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _shiftHours(DutyShift s) => switch (s) {
        DutyShift.morning => '8 am – 3 pm',
        DutyShift.evening => '3 pm – 10 pm',
        DutyShift.night => '10 pm – 8 am',
      };

  final List<String> _picked = []; // an old team of N: who goes
  // a full-time team: who works the Morning, Evening and Night shift first
  final Map<DutyShift, String> _byShift = {};
  bool _busy = false;

  bool get _rotation => widget.request['rotation'] == true;

  Future<void> _assign() async {
    setState(() => _busy = true);
    try {
      if (_rotation) {
        await CareDutyService.createTeam(
          request: widget.request,
          agencyId: widget.agencyId,
          agencyName: widget.agencyName,
          byShift: Map.of(_byShift),
        );
        _byShift.clear();
        widget.onDone(
            'Full-time team placed. They see the duty roster now, and the hospital is told.');
        return;
      }
      final failed = await _Cp.allocateTeam(
          widget.request, widget.agencyId, _picked.toList());
      _picked.clear();
      widget.onDone(
          failed.isEmpty
              ? 'Sent to the hospital. They are now duties in your Control Room.'
              : 'Some could not be allocated: ${failed.join('; ')}',
          error: failed.isNotEmpty);
    } catch (e) {
      widget.onDone(ErrorMessages.of(e, action: 'assign the team'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rotation) return _rotationCard();
    final r = widget.request;
    final size = _Cp.teamSizeOf(r);
    final allocated = _Cp.listOf(r['allocatedUids']);
    final remaining = size - allocated.length;
    final applicants = (r['applicants'] as Map?) ?? const {};
    final mine = [
      for (final e in applicants.entries)
        if (e.value is Map &&
            e.value['agencyId'] == widget.agencyId &&
            !allocated.contains(e.key))
          (uid: e.key.toString(), data: Map<String, dynamic>.from(e.value as Map))
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.primary, width: 5)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_hospital_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((r['hospitalName'] ?? 'Hospital').toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppTheme.darkNavy)),
                        const SizedBox(height: 3),
                        Text(
                          _rotation
                              ? '${_Cp.teamKindLabel(r)} from ${r['anchor']}'
                                  '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}'
                              : 'Team of $size · ${_Cp.dayLabel(r, DateTime.now())} · ${_Cp.timeRange(r)}'
                                  '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.line),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('₹${toNum(r['pay'])?.round() ?? 0} per ${_rotation ? 'duty' : 'doctor'}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkNavy)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$remaining still needed',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (mine.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.page,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('None of your care physicians has accepted yet.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                )
              else ...[
                Text(
                    _rotation
                        ? '${mine.length} of your doctors accepted. Tick exactly 3 for the full-time team, in the order A, B, C:'
                        : '${mine.length} of your doctors accepted. Pick up to $remaining:',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textBody)),
                const SizedBox(height: 8),
                for (final m in mine)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: AppColors.page,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      value: _picked.contains(m.uid),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      secondary: _picked.contains(m.uid) && _rotation
                          ? CircleAvatar(
                              radius: 13,
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              child: Text(CareDutyRoster.letters[_picked.indexOf(m.uid)],
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))
                          : null,
                      title: Text((m.data['name'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkNavy)),
                      subtitle: Text([
                        (m.data['qualification'] ?? '').toString(),
                        if ((m.data['currentHospital'] ?? '').toString().isNotEmpty)
                          'moving from ${m.data['currentHospital']}',
                      ].where((x) => x.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  if (_picked.length < remaining && !_picked.contains(m.uid)) {
                                    _picked.add(m.uid);
                                  }
                                } else {
                                  _picked.remove(m.uid);
                                }
                              }),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ||
                            _picked.isEmpty ||
                            (_rotation && _picked.length != 3)
                        ? null
                        : _assign,
                    icon: const Icon(Icons.groups_rounded, size: 18),
                    label: Text(_busy
                        ? 'Assigning…'
                        : _rotation
                            ? 'Place the full-time team (${_picked.length} of 3)'
                            : 'Assign ${_picked.length} to the hospital'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
