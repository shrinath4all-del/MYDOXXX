import '../../../services/app_database.dart';
import '../../../utils/safe_cast.dart';
import 'package:flutter/material.dart';

import '../../../services/care_agency_service.dart';
import '../../../models/care_duty_roster.dart';
import '../../../services/technician_duty_service.dart';
import '../../../services/technician_staffing_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/responsive.dart';
import '../../../utils/stream_cache.dart';
import '../../../constants/app_colors.dart';

typedef _Cp = TechnicianStaffingService;

/// Technician requests that hospitals posted. This is the only kind of
/// request a partner agency sees: a patient's home-care booking never shows
/// here. The agency assigns one of its own technicians to a request.
class TechnicianHospitalRequestsScreen extends StatefulWidget {
  final Map<String, dynamic> agency;
  const TechnicianHospitalRequestsScreen({super.key, required this.agency});

  @override
  State<TechnicianHospitalRequestsScreen> createState() => _HospitalRequestsScreenState();
}

class _HospitalRequestsScreenState extends State<TechnicianHospitalRequestsScreen> {
  final StreamCache _streams = StreamCache();
  String _filter = 'team'; // team | open | mine

  String get _agencyId => (widget.agency['id'] ?? widget.agency['uid'] ?? '').toString();

  /// Open requests in the agency's areas (no areas = any) and the requests
  /// this agency already took.
  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> all) {
    final areas = _Cp.listOf(widget.agency['areas']);
    final now = DateTime.now();
    return [
      for (final r in all)
        if (r['postedBy'] == 'hospital' &&
            (_filter == 'approval'
                ? (r['status'] == 'pending_agency' &&
                    (r['pendingAgencyId'] ?? '').toString() == _agencyId)
                : _filter == 'open'
                ? (r['status'] == 'open' &&
                    (_Cp.shiftStart(r)?.isAfter(now) ?? false) &&
                    _Cp.inMyAreas(areas, r['area']?.toString()))
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

  Future<void> _decide(Map<String, dynamic> request,
      {required bool approve}) async {
    try {
      if (approve) {
        await _Cp.approveRequest(request, _agencyId);
        _snack('Approved. ${request['claimedByName']} is allocated to the hospital.');
      } else {
        await _Cp.declineRequest(request, _agencyId);
        _snack('Declined. The request is open for other technicians again.');
      }
    } catch (e) {
      _snack(ErrorMessages.of(e, action: approve ? 'approve the request' : 'decline the request'),
          error: true);
    }
  }

  Future<void> _assign(Map<String, dynamic> request) async {
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
      _snack(ErrorMessages.of(e, action: 'assign the technician'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        appBar: AppBar(title: const Text('Hospital requests')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(
                label: const Text('Team requests'),
                selected: _filter == 'team',
                onSelected: (_) => setState(() => _filter = 'team'),
              ),
              ChoiceChip(
                label: const Text('Open requests'),
                selected: _filter == 'open',
                onSelected: (_) => setState(() => _filter = 'open'),
              ),
              ChoiceChip(
                label: const Text('Taken by us'),
                selected: _filter == 'mine',
                onSelected: (_) => setState(() => _filter = 'mine'),
              ),
            ]),
          ),
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
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _filter == 'approval'
                            ? 'No requests are waiting for your approval.'
                            : _filter == 'open'
                                ? 'No open technician requests from hospitals right now.'
                                : 'You have not taken any hospital request yet.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _card(list[i]),
                );
              },
            ),
          ),
        ]),
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
          final areas = _Cp.listOf(widget.agency['areas']);
          final now = DateTime.now();
          final list = [
            for (final r in snap.data!)
              if (r['status'] == 'open' &&
                  (_Cp.shiftStart(r)?.isAfter(now) ?? false) &&
                  _Cp.inMyAreas(areas, r['area']?.toString()))
                r
          ];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No team requests from hospitals right now.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: r['urgent'] == true ? AppColors.danger : AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text((r['hospitalName'] ?? 'Hospital').toString(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.darkNavy)),
          ),
          if (r['urgent'] == true)
            const Text('URGENT',
                style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        Text(
          '${_Cp.dayLabel(r, DateTime.now())} · ${_Cp.timeRange(r)}'
          '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 4),
        Text('Pay ₹${toNum(r['pay'])?.round() ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (taken && (r['claimedByName'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Assigned to ${r['claimedByName']}',
                style: TextStyle(color: AppColors.successDark, fontSize: 12.5)),
          ),
        if (r['status'] == 'pending_agency') ...[
          const SizedBox(height: 6),
          Text(
              '${r['claimedByName'] ?? 'Your technician'} accepted this request. '
              'Approve to allocate the technician to the hospital.',
              style: TextStyle(color: AppColors.orange, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _decide(r, approve: false),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _decide(r, approve: true),
                child: const Text('Approve'),
              ),
            ),
          ]),
        ],
        if (!taken && r['status'] != 'pending_agency') ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _assign(r),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Assign a technician'),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The agency's own technicians that have an app account (only they can
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
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: CareAgencyService.doctorsStream(agencyId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()));
            }
            final doctors = [
              for (final d in snap.data!)
                if (d['active'] != false &&
                    (d['userUid'] ?? '').toString().isNotEmpty)
                  d
            ];
            if (doctors.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'None of your technicians has an app account yet. Add them in Technicians with their mobile number, and ask them to sign in.',
                    textAlign: TextAlign.center),
              );
            }
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Choose a technician',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                for (final d in doctors)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text((d['name'] ?? '').toString()),
                    subtitle: Text((d['qualification'] ?? '').toString()),
                    onTap: () => Navigator.pop(context, d),
                  ),
              ],
            );
          },
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
  /// A full-time team: the best 10 applicants (any technician), and the
  /// agency picks who works the Morning, Evening and Night shift.
  Widget _rotationCard() {
    final r = widget.request;
    final top = _Cp.shortlist(r);
    final applied = _Cp.listOf(r['applicantUids']).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((r['hospitalName'] ?? 'Hospital').toString(),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.darkNavy)),
        const SizedBox(height: 4),
        Text(
          'Full-time team of 3, weekly rotation from ${r['anchor']}'
          '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
        ),
        Text('₹${toNum(r['pay'])?.round() ?? 0} per month for each technician',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 10),
        if (top.length < 3)
          Text(
              applied == 0
                  ? 'No technician has applied yet.'
                  : 'Only $applied applied so far. You need at least 3 to place the team.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5))
        else ...[
          Text(
              '$applied applied. Choose 3 of the best ${top.length} (fewest no-shows, then most experience). The 3 you pick are told they are selected; the others see "Not selected" in their Applied tab:',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          for (final a in top)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                  '• ${a.data['name'] ?? ''}'
                  ' · ${a.data['experienceYears'] ?? 0} yrs'
                  '${((a.data['noShows'] as num?) ?? 0) > 0 ? ' · ${a.data['noShows']} no-show(s)' : ''}'
                  '${(a.data['agencyName'] ?? '').toString().isEmpty ? ' · freelancer' : ''}'
                  '${(a.data['currentHospital'] ?? '').toString().isEmpty ? '' : ' · moving from ${a.data['currentHospital']}'}',
                  style: const TextStyle(fontSize: 12.5)),
            ),
          const SizedBox(height: 10),
          const Text('Who works which shift?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const Text(
              'The rotation then moves each of them to the next shift every week.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          for (final shift in TechnicianDutyService.teamShifts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy || _byShift.length != 3 ? null : _assign,
              icon: const Icon(Icons.groups_rounded, size: 18),
              label: Text(_busy
                  ? 'Placing…'
                  : 'Place the full-time team (${_byShift.length} of 3)'),
            ),
          ),
        ],
      ]),
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
        await TechnicianDutyService.createTeam(
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((r['hospitalName'] ?? 'Hospital').toString(),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.darkNavy)),
        const SizedBox(height: 4),
        Text(
          _rotation
              ? 'Full-time team of 3, weekly rotation from ${r['anchor']}'
                  '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}'
              : 'Team of $size · ${_Cp.dayLabel(r, DateTime.now())} · ${_Cp.timeRange(r)}'
                  '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
        ),
        Text('₹${toNum(r['pay'])?.round() ?? 0} per ${_rotation ? 'duty' : 'technician'} · $remaining still needed',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 8),
        if (mine.isEmpty)
          const Text('None of your technicians has accepted yet.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5))
        else ...[
          Text(
              _rotation
                  ? '${mine.length} of your technicians accepted. Tick exactly 3 for the full-time team, in the order A, B, C:'
                  : '${mine.length} of your technicians accepted. Pick up to $remaining:',
              style: const TextStyle(fontSize: 12.5)),
          for (final m in mine)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(m.uid),
              secondary: _picked.contains(m.uid) && _rotation
                  ? CircleAvatar(
                      radius: 13,
                      child: Text(CareDutyRoster.letters[_picked.indexOf(m.uid)]))
                  : null,
              title: Text((m.data['name'] ?? '').toString()),
              subtitle: Text([
                (m.data['qualification'] ?? '').toString(),
                if ((m.data['currentHospital'] ?? '').toString().isNotEmpty)
                  'moving from ${m.data['currentHospital']}',
              ].where((x) => x.isNotEmpty).join(' · ')),
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
          const SizedBox(height: 6),
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
            ),
          ),
        ],
      ]),
    );
  }
}
