import 'dart:async';
import '../../utils/form_utils.dart';
import '../../utils/safe_cast.dart';

import 'package:flutter/material.dart';

import '../../models/care_duty_roster.dart';
import '../../services/nurse_duty_rate_service.dart';
import '../../services/nurse_duty_service.dart';
import '../../services/nurse_staffing_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../utils/stream_cache.dart';
import '../../utils/validators.dart';
import '../agency/control_room_widgets.dart' show formatInr;
import '../care_physician/cp_widgets.dart';
import '../../constants/app_colors.dart';

typedef _Cp = NurseStaffingService;

/// A hospital a shift or job can be posted for.
typedef NurseHospitalChoice = ({String id, String name, String area});

/// Hospitals, nurse agencies and the admin post per-shift duties
/// and full-time jobs for nurses here, and see who claimed a shift
/// or showed interest in a job.
class NurseShiftBoardScreen extends StatefulWidget {
  final String postedBy; // 'hospital' | 'agency' | 'admin'
  final String posterId;
  final String posterName;
  final String? agencyId;

  /// The hospitals this poster can post for (live).
  final Stream<List<NurseHospitalChoice>> hospitals;

  /// 'shifts' | 'teams' | 'jobs': the tab to open first.
  final String initialTab;

  /// Open the post form straight away (Book Locum / Book Team).
  final bool openPost;

  NurseShiftBoardScreen({
    super.key,
    required this.postedBy,
    required this.posterId,
    required this.posterName,
    this.agencyId,
    this.initialTab = 'shifts',
    this.openPost = false,
    required Stream<List<NurseHospitalChoice>> hospitals,
  }) : hospitals = _replay(hospitals);

  /// The post-shift and post-job screens each listen to the hospitals, one
  /// after the other: a one-shot stream (Stream.value) can only be listened
  /// to once, so every listener gets the latest list again here.
  static Stream<T> _replay<T>(Stream<T> source) {
    T? last;
    var has = false;
    final live = StreamController<T>.broadcast();
    source.listen((v) {
      last = v;
      has = true;
      live.add(v);
    }, onError: live.addError);
    return Stream<T>.multi((c) {
      if (has) c.add(last as T);
      final sub = live.stream.listen(c.add, onError: c.addError);
      c.onCancel = sub.cancel;
    }, isBroadcast: true);
  }

  @override
  State<NurseShiftBoardScreen> createState() => _ShiftBoardScreenState();
}

class _ShiftBoardScreenState extends State<NurseShiftBoardScreen> {
  final StreamCache _streams = StreamCache();
  late String _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    if (widget.openPost) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _post();
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  Future<void> _post({Map<String, dynamic>? job}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _tab == 'shifts'
          ? NursePostShiftScreen(board: widget)
          : _tab == 'teams'
              ? NursePostShiftScreen(board: widget, team: true)
              : NursePostJobScreen(board: widget, job: job),
    ));
    if (saved == true) {
      _snack(_tab == 'shifts'
          ? (widget.postedBy == 'hospital'
              ? 'Locum request posted. Agency nurses see it first; after 5 minutes it opens to everyone.'
              : 'Shift posted. Nurses in that area can claim it now.')
          : _tab == 'teams'
              ? 'Full-time team requested. Agency nurses can accept; their agency picks the three who come.'
              : (job == null ? 'Job posted.' : 'Job updated.'));
    }
  }

  /// The hospital enters the OTP; the nurse must be within 500 m.
  Future<void> _verify(Map<String, dynamic> s) async {
    final c = TextEditingController();
    final otp = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrival OTP'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Ask ${s['claimedByName'] ?? 'the nurse'} for the 4-digit OTP shown in their app.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
            decoration: const InputDecoration(counterText: ''),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Confirm arrival')),
        ],
      ),
    );
    if (otp == null || otp.length != 4) return;
    try {
      final late = await _Cp.verifyArrival(s, otp, widget.posterId);
      _snack(late > 0
          ? 'Arrival confirmed ($late min late). The shift has started.'
          : 'Arrival confirmed. The shift has started.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'confirm the arrival'), error: true);
    }
  }

  Future<void> _cancel(Map<String, dynamic> s) async {
    final claimed = s['status'] == 'claimed';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this shift?'),
        content: Text(claimed
            ? '${s['claimedByName']} has claimed it. They will see it as cancelled.'
            : 'Nurses will no longer see it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel shift'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _Cp.cancelShift(s);
      _snack('Shift cancelled.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'cancel the shift'), error: true);
    }
  }

  void _interests(Map<String, dynamic> job) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _InterestsSheet(job: job),
      );

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Scaffold(
        backgroundColor: CpColors.page,
        appBar: AppBar(
            title: Text(widget.postedBy == 'hospital' ? 'Nurses' : 'Shifts & jobs')),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: CpColors.navy,
          foregroundColor: Colors.white,
          onPressed: () => _post(),
          icon: const Icon(Icons.add_rounded),
          label: Text(_tab == 'shifts'
              ? (widget.postedBy == 'hospital' ? 'Book locum' : 'Post shift')
              : _tab == 'teams'
                  ? 'Book full-time team'
                  : 'Post job'),
        ),
        body: Column(children: [
          const SizedBox(height: 10),
          CpFilterChips(
            options: {
              'shifts': widget.postedBy == 'hospital' ? 'Locum shifts' : 'Shifts',
              if (widget.postedBy == 'hospital') 'teams': 'Full-time team',
              if (widget.postedBy == 'hospital') 'leave': 'Leave requests',
              // a hospital's long-term cover is a team (weekly rotation), not a job post
              if (widget.postedBy != 'hospital') 'jobs': 'Full-time jobs',
            },
            selected: _tab,
            onSelected: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 10),
          Expanded(
              child: _tab == 'shifts'
                  ? _shifts()
                  : _tab == 'teams'
                      ? _teams()
                      : _tab == 'leave'
                          ? _leave()
                          : _jobs()),
        ]),
      ),
    );
  }

  Widget _shifts() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get(
            'shifts', () => _Cp.posterShiftsStream(widget.posterId)),
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'your shifts');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final now = DateTime.now();
          _Cp.markNoShows(snap.data!, now);
          if (snap.data!.isEmpty) {
            return const CpEmpty('🗓️',
                'No shifts posted yet. Tap "Post shift" to post a duty; nurses in that area can claim it.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final s in snap.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NursePostedShiftCard(
                      shift: s,
                      now: now,
                      onCancel: () => _cancel(s),
                      onVerify: widget.postedBy == 'hospital' &&
                              _Cp.usesArrivalOtp(s)
                          ? () => _verify(s)
                          : null),
                ),
            ],
          );
        },
      );

  /// Nurses' leave requests: the hospital approves or declines.
  Widget _leave() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('leave',
            () => NurseDutyService.leaveRequestsOfHospital(widget.posterId)),
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'leave requests');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data!.isEmpty) {
            return const CpEmpty('🗓️',
                'No leave requests from your full-time nurses.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final r in snap.data!) _leaveCard(r),
            ],
          );
        },
      );

  Future<void> _decideLeave(Map<String, dynamic> r, bool approve) async {
    try {
      await NurseDutyService.hospitalDecideLeave(r['id'].toString(),
          approve: approve);
      _snack(approve ? 'Leave approved.' : 'Leave declined.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'answer the leave request'),
          error: true);
    }
  }

  Widget _leaveCard(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    final slot = DutySlot.parse((r['sourceKey'] ?? '').toString());
    final (label, color) = switch (status) {
      'awaiting_hospital' => ('NEEDS YOUR ANSWER', const Color(0xFFD97706)),
      'declined' => ('DECLINED', CpColors.red),
      'accepted' => ('COVERED', CpColors.green),
      'withdrawn' => ('WITHDRAWN', CpColors.muted),
      _ => ('APPROVED', CpColors.green),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                '${r['requesterName'] ?? 'Nurse'} asks for leave',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          CpTag(label, color),
        ]),
        const SizedBox(height: 4),
        if (slot != null)
          Text(
              '${slot.date.day}/${slot.date.month}/${slot.date.year} · ${slot.shift.label} ${slot.shift.timeText}',
              style: const TextStyle(fontSize: 12.5, color: CpColors.muted)),
        if ((r['reason'] ?? '').toString().isNotEmpty)
          Text('Reason: ${r['reason']}',
              style: const TextStyle(fontSize: 12.5)),
        if ((r['note'] ?? '').toString().isNotEmpty)
          Text('${r['note']}',
              style: const TextStyle(fontSize: 12.5, color: CpColors.muted)),
        if (status == 'accepted' &&
            (r['acceptedByName'] ?? '').toString().isNotEmpty)
          Text('Covered by ${r['acceptedByName']}',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (status == 'awaiting_hospital') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: () => _decideLeave(r, false),
                  child: const Text('Decline')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                  onPressed: () => _decideLeave(r, true),
                  child: const Text('Approve leave')),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _teams() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('teams',
            () => _Cp.posterTeamRequestsStream(widget.posterId)),
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'your team requests');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data!.isEmpty) {
            return const CpEmpty('👥',
                'No team requested yet. Tap "Book team" to get 3 full-time nurses on a weekly rotation; the agency picks who comes.');
          }
          final now = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final r in snap.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TeamRequestCard(
                    request: r,
                    now: now,
                  ),
                ),
            ],
          );
        },
      );

  Widget _jobs() => StreamBuilder<List<Map<String, dynamic>>>(
        stream:
            _streams.get('jobs', () => _Cp.posterJobsStream(widget.posterId)),
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(error: snap.error, what: 'your jobs');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data!.isEmpty) {
            return const CpEmpty('🏥',
                'No full-time jobs posted yet. Tap "Post job" to hire a nurse; nurses who fit can express interest.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final j in snap.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NursePostedJobCard(
                    job: j,
                    onInterests: () => _interests(j),
                    onEdit: () {
                      _post(job: j);
                    },
                    onActive: (v) async {
                      try {
                        await _Cp.setJobActive(j['id'].toString(), v);
                      } catch (e) {
                        _snack(ErrorMessages.of(e, action: 'update the job'),
                            error: true);
                      }
                    },
                  ),
                ),
            ],
          );
        },
      );
}

/// A team request: how many accepted, who the agency allocated.
class _TeamRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final DateTime now;
  const _TeamRequestCard({required this.request, required this.now});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final status = (r['status'] ?? '').toString();
    final size = _Cp.teamSizeOf(r);
    final allocated = _Cp.listOf(r['allocatedUids']).length;
    final accepted = _Cp.listOf(r['applicantUids']).length;
    final rotation = r['rotation'] == true;
    final start = _Cp.shiftStart(r);
    final expired = status == 'open' && start != null && !start.isAfter(now);
    final (label, color) = expired
        ? ('NOT FILLED', CpColors.muted)
        : switch (status) {
            'open' => ('OPEN', const Color(0xFFD97706)),
            'filled' => ('TEAM READY', CpColors.green),
            'cancelled' => ('CANCELLED', CpColors.muted),
            _ => ('CLOSED', CpColors.muted),
          };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                r['rotation'] == true
                    ? 'Full-time team of $size'
                    : 'Team of $size nurses',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: CpColors.ink)),
          ),
          CpTag(label, color),
        ]),
        const SizedBox(height: 4),
        Text(
            rotation
                ? '${(r['fixedShift'] ?? '').toString().isEmpty ? 'Weekly rotation' : 'One nurse, ${r['fixedShift']} shift every day'} from ${r['anchor']}'
                    '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}'
                : '${_Cp.dayLabel(r, now)} · ${_Cp.slotLabel(r)} (${_Cp.timeRange(r)})'
                    '${(r['area'] ?? '').toString().isEmpty ? '' : ' · ${r['area']}'}',
            style: const TextStyle(fontSize: 12, color: CpColors.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          CpInfo('✋ $accepted accepted'),
          CpInfo('✅ $allocated of $size allocated'),
          CpInfo(r['payPeriod'] == 'month'
              ? '₹${toNum(r['pay'])?.round() ?? 0} / month each'
              : '₹${toNum(r['pay'])?.round() ?? 0} per nurse'),
        ]),
        if (r['shiftAssignments'] is Map) ...[
          const SizedBox(height: 8),
          for (final e in const {
            'morning': 'Morning',
            'evening': 'Evening',
            'night': 'Night',
          }.entries)
            if ((r['shiftAssignments'] as Map)[e.key] != null)
              Text('${e.value} (first week): ${(r['shiftAssignments'] as Map)[e.key]}',
                  style: const TextStyle(fontSize: 12.5, color: CpColors.ink)),
        ] else if (_Cp.listOf(r['allocatedNames']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Allocated: ${_Cp.listOf(r['allocatedNames']).join(', ')}',
              style: const TextStyle(fontSize: 12.5, color: CpColors.ink)),
        ],
      ]),
    );
  }
}

/// A posted shift: status, who claimed it, Cancel.
class NursePostedShiftCard extends StatelessWidget {
  final Map<String, dynamic> shift;
  final DateTime now;
  final VoidCallback onCancel;

  /// A hospital enters the OTP the nurse shows (null: not offered).
  final VoidCallback? onVerify;
  const NursePostedShiftCard(
      {super.key,
      required this.shift,
      required this.now,
      required this.onCancel,
      this.onVerify});

  @override
  Widget build(BuildContext context) {
    final type = shift['dutyType']?.toString();
    final status = (shift['status'] ?? '').toString();
    final (label, color) = switch (status) {
      'open' => ('OPEN', AppColors.warning),
      'pending_agency' => ('AWAITING AGENCY', AppColors.warning),
      'claimed' => ('CLAIMED', AppColors.blue),
      'on_duty' => ('ON DUTY', CpColors.green),
      'completed' => ('COMPLETED', CpColors.green),
      'absent' => ('NO-SHOW', CpColors.red),
      'unfilled' => ('NOT FILLED', CpColors.muted),
      _ => ('CANCELLED', CpColors.muted),
    };
    final start = _Cp.shiftStart(shift);
    final canCancel = (status == 'open' ||
            status == 'claimed' ||
            status == 'pending_agency') &&
        start != null &&
        start.isAfter(now);
    final late = toNum(shift['lateMinutes'])?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CpEmojiTile(_Cp.dutyEmoji(type),
                CpColors.duty(type, urgent: shift['urgent'] == true)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((shift['hospitalName'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: CpColors.ink)),
                  Text(
                      '${_Cp.dutyLabel(type)} · ${_Cp.dayLabel(shift, now)} · '
                      '${_Cp.slotLabel(shift)} (${_Cp.timeRange(shift)})',
                      style:
                          const TextStyle(fontSize: 12, color: CpColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatInr(toNum(shift['pay']) ?? 0),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: CpColors.navy)),
              const SizedBox(height: 4),
              CpTag(label, color, filled: false),
            ]),
          ]),
          if ((shift['claimedByName'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
                '👩‍⚕️ ${shift['claimedByName']}'
                '${(shift['claimedByPhone'] ?? '').toString().isEmpty ? '' : ' · ${shift['claimedByPhone']}'}'
                '${late > 0 ? ' · checked in $late min late' : ''}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CpColors.ink)),
          ],
          if (onVerify != null &&
              status == 'claimed' &&
              _Cp.canCheckIn(shift, now)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onVerify,
                icon: const Icon(Icons.pin_rounded, size: 18),
                label: const Text('Enter arrival OTP'),
              ),
            ),
          ],
          if (status == 'on_duty' && shift['arrivalDistanceM'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Arrival confirmed · ${shift['arrivalDistanceM']} m from the hospital',
                  style: const TextStyle(fontSize: 12, color: CpColors.green)),
            ),
          if (canCancel)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Cancel shift',
                    style: TextStyle(color: AppColors.danger)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A posted job: interests count, pause / resume, edit.
class NursePostedJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onInterests;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActive;
  const NursePostedJobCard({
    super.key,
    required this.job,
    required this.onInterests,
    required this.onEdit,
    required this.onActive,
  });

  @override
  Widget build(BuildContext context) {
    final interested = _Cp.listOf(job['interestedUids']).length;
    final active = job['active'] != false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((job['title'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: CpColors.ink)),
                  Text(
                      '${job['hospitalName'] ?? ''} · ${_Cp.salaryLabel(job)} / month · '
                      '${job['openings'] ?? 1} opening(s)',
                      style:
                          const TextStyle(fontSize: 12, color: CpColors.muted)),
                ],
              ),
            ),
            Switch(value: active, onChanged: onActive),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: onInterests,
              icon: const Icon(Icons.people_alt_outlined, size: 18),
              label: Text('$interested interested'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
          ]),
          if (!active)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Paused — nurses do not see this job.',
                  style: TextStyle(fontSize: 12, color: CpColors.muted)),
            ),
        ],
      ),
    );
  }
}

class _InterestsSheet extends StatelessWidget {
  final Map<String, dynamic> job;
  const _InterestsSheet({required this.job});

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) =>
            StreamBuilder<List<Map<String, dynamic>>>(
          stream: _Cp.interestsStream(job['id'].toString()),
          builder: (context, snap) {
            final list = snap.data ?? const [];
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                Text('Interested in ${job['title']}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Call them to take it forward.',
                    style: TextStyle(color: CpColors.muted)),
                const SizedBox(height: 14),
                if (snap.hasError)
                  LoadErrorView(error: snap.error, what: 'interested nurses')
                else if (!snap.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (list.isEmpty)
                  const CpEmpty('🕐', 'No one has expressed interest yet.')
                else
                  for (final p in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: cpCard(),
                      child: Row(children: [
                        const Text('🩺', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((p['name'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              Text(
                                  [
                                    (p['qualification'] ?? '').toString(),
                                    '${p['experienceYears'] ?? 0} yrs',
                                    if ((p['regNo'] ?? '').toString().isNotEmpty)
                                      'Reg ${p['regNo']}',
                                  ].where((e) => e.isNotEmpty).join(' · '),
                                  style: const TextStyle(
                                      fontSize: 12, color: CpColors.muted)),
                              Text((p['phone'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: CpColors.navy)),
                            ],
                          ),
                        ),
                        if (p['verified'] == true)
                          const CpTag('✓ VERIFIED', CpColors.green,
                              filled: false),
                      ]),
                    ),
              ],
            );
          },
        ),
      );
}

// ------------------------------------------------------------------ forms

/// Shared: hospital + area pickers (areas live from 'location_master').
mixin _HospitalAreaPicker<T extends StatefulWidget> on State<T> {
  NurseShiftBoardScreen get board;
  List<NurseHospitalChoice> hospitals = [];
  List<String> areas = [];
  NurseHospitalChoice? hospital;
  String? area;
  StreamSubscription? _hSub;
  StreamSubscription? _aSub;

  void listenHospitalsAndAreas({String? hospitalId, String? initialArea}) {
    area = initialArea;
    _hSub = board.hospitals.listen((h) {
      if (!mounted) return;
      setState(() {
        hospitals = h;
        hospital ??= h.where((x) => x.id == hospitalId).firstOrNull ??
            (h.length == 1 ? h.first : null);
        if (area == null && hospital != null) area = matchArea(hospital!.area) ?? ownArea();
      });
    }, onError: (_) {});
    _aSub = FirestoreService.nameMasterStream('location_master').listen((a) {
      if (!mounted) return;
      setState(() {
        areas = a;
        if (area == null && hospital != null) area = matchArea(hospital!.area) ?? ownArea();
      });
    }, onError: (_) {});
  }

  /// A hospital posting for itself uses the area of its own profile.
  String? ownArea() {
    if (board.postedBy != 'hospital' || hospital == null) return null;
    final raw = hospital!.area.trim();
    return raw.isEmpty ? null : raw;
  }

  bool get fixedHospital => board.postedBy == 'hospital' && hospitals.length <= 1;

  /// Nurses pick areas from the master list, so a shift's area
  /// must be one of those names: "Kothrud, Pune" -> "Kothrud".
  String? matchArea(String raw) {
    final text = raw.toLowerCase();
    if (text.isEmpty) return null;
    for (final a in areas) {
      if (a.toLowerCase() == text) return a;
    }
    for (final a in areas) {
      if (text.contains(a.toLowerCase())) return a;
    }
    return null;
  }

  void cancelPickers() {
    _hSub?.cancel();
    _aSub?.cancel();
  }

  List<Widget> hospitalAndAreaFields() {
    if (fixedHospital) {
      // the hospital's own name; its area comes from its profile
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.local_hospital_rounded, color: CpColors.navy),
            const SizedBox(width: 10),
            Expanded(
              child: Text(hospital?.name ?? 'Loading…',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: CpColors.ink)),
            ),
          ]),
        ),
      ];
    }
    final areaOptions = {...areas, if (area != null) area!}.toList()..sort();
    return [
      const _Label('HOSPITAL'),
      DropdownButtonFormField<String>(
        menuMaxHeight: 320,
        // ignore: deprecated_member_use
        value: hospital?.id,
        isExpanded: true,
        hint: Text(hospitals.isEmpty ? 'Loading hospitals…' : 'Pick a hospital'),
        items: [
          for (final h in hospitals)
            DropdownMenuItem(value: h.id, child: Text(h.name)),
        ],
        validator: (v) => v == null ? 'Pick the hospital' : null,
        onChanged: (id) => setState(() {
          hospital = hospitals.firstWhere((h) => h.id == id);
          area = matchArea(hospital!.area) ?? area;
        }),
      ),
      const SizedBox(height: 14),
      const _Label('AREA'),
      DropdownButtonFormField<String>(
        menuMaxHeight: 320,
        // ignore: deprecated_member_use
        value: area,
        isExpanded: true,
        hint: const Text('Pick the area'),
        items: [
          for (final a in areaOptions)
            DropdownMenuItem(value: a, child: Text(a)),
        ],
        validator: (v) => v == null ? 'Pick the area' : null,
        onChanged: (v) => setState(() => area = v),
      ),
    ];
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: CpColors.ink)),
      );
}

/// Tappable chips for a set of keys.
Widget _multiChips(Map<String, String> options, Set<String> selected,
        void Function(String) onToggle) =>
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final e in options.entries)
        FilterChip(
          label: Text(e.value),
          selected: selected.contains(e.key),
          onSelected: (_) => onToggle(e.key),
        ),
    ]);

class NursePostShiftScreen extends StatefulWidget {
  final NurseShiftBoardScreen board;

  /// A team request (several nurses at once) instead of one shift.
  final bool team;
  const NursePostShiftScreen({super.key, required this.board, this.team = false});

  @override
  State<NursePostShiftScreen> createState() => _PostShiftScreenState();
}

class _PostShiftScreenState extends State<NursePostShiftScreen>
    with _HospitalAreaPicker {
  @override
  NurseShiftBoardScreen get board => widget.board;

  final _formKey = GlobalKey<FormState>();
  final _pay = TextEditingController();
  final _teamSize = TextEditingController(text: '3');
  String _dutyType = 'ward';
  String _specialty = '';
  final Set<String> _procedures = {};
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String _slot = 'morning';
  late String _start = _Cp.slots['morning']!.$2;
  late String _end = _Cp.slots['morning']!.$3;
  bool _urgent = false;
  bool _saving = false;
  // a team is full time: 3 nurses (A, B, C) on a weekly rotation
  // from the chosen date, with no end date
  late final bool _rotation = widget.team;
  // which shift(s) a full-time team covers: all (3 physicians on a weekly
  // rotation) or one fixed shift (1 physician, every day)
  String _teamShift = 'all';
  // the master-table rates, kept as they arrive (the form moves when the
  // specialty box appears, so a one-time stream cannot be listened to again)
  Map<String, NurseDutyRate>? _rates;
  StreamSubscription<Map<String, NurseDutyRate>>? _rateSub;

  // a hospital picks ward, ICU or specialty duty and a greeting shift; its
  // area is its own profile's
  bool get _hospitalPost => board.postedBy == 'hospital';
  static const _hospitalDuties = {'ward', 'icu', 'specialty'};

  @override
  void initState() {
    super.initState();
    listenHospitalsAndAreas();
    _rateSub = NurseDutyRates.stream().listen((r) {
      if (mounted) setState(() => _rates = r);
    }, onError: (_) {
      if (mounted) setState(() => _rates = const {});
    });
  }

  @override
  void dispose() {
    _rateSub?.cancel();
    cancelPickers();
    _pay.dispose();
    _teamSize.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      // a team can start any day after today
      firstDate: _rotation
          ? DateTime(now.year, now.month, now.day + 1)
          : DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime(bool start) async {
    final parts = (start ? _start : _end).split(':');
    final t = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (t == null) return;
    final v =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => start ? _start = v : _end = v);
  }

  Future<void> _save() async {
    if (!FormUtils.validate(_formKey)) return;
    if (area == null || area!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your hospital profile has no area. Add it in your profile, then post again.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_hospitalPost) _pay.text = '1'; // the master-table rate is used
      if (widget.team) {
        if (_rotation) {
          final one = _teamShift != 'all';
          _teamSize.text = one ? '1' : '3';
          const hours = {
            'all': ('morning', '08:00', '15:00'),
            'morning': ('morning', '08:00', '15:00'),
            'evening': ('evening', '15:00', '22:00'),
            'night': ('night', '22:00', '08:00'),
          };
          final h = hours[_teamShift]!;
          _slot = h.$1;
          _start = h.$2;
          _end = h.$3;
        }
        await _Cp.postTeamRequest(
          rotation: _rotation,
          fixedShift: _rotation && _teamShift != 'all' ? _teamShift : '',
          posterId: board.posterId,
          posterName: board.posterName,
          hospitalId: hospital!.id,
          hospitalName: hospital!.name,
          area: area!,
          dutyType: _dutyType,
          specialty: _specialty,
          procedures: _procedures.toList(),
          date: _Cp.dateKey(_date),
          slot: _slot,
          start: _start,
          end: _end,
          pay: int.parse(_pay.text.trim()),
          teamSize: int.parse(_teamSize.text.trim()),
          urgent: _urgent,
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }
      await _Cp.postShift(
        postedBy: board.postedBy,
        posterId: board.posterId,
        posterName: board.posterName,
        agencyId: board.agencyId,
        hospitalId: hospital!.id,
        hospitalName: hospital!.name,
        area: area!,
        dutyType: _dutyType,
        specialty: _specialty,
        procedures: _procedures.toList(),
        date: _Cp.dateKey(_date),
        slot: _slot,
        start: _start,
        end: _end,
        pay: int.parse(_pay.text.trim()),
        urgent: _urgent,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'post the shift')),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = {'date': _Cp.dateKey(_date), 'start': _start, 'end': _end};
    return ResponsiveCenter(
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.team
                ? 'Book a full-time team'
                : (board.postedBy == 'hospital' ? 'Book a locum' : 'Post a shift'))),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(Responsive.gutter(context)),
            children: [
              ...hospitalAndAreaFields(),
              const SizedBox(height: 14),
              const _Label('DUTY TYPE'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _Cp.dutyTypes.entries)
                  if (!_hospitalPost || _hospitalDuties.contains(e.key))
                    ChoiceChip(
                      label: Text('${e.value.$1} ${e.value.$2}'),
                      selected: _dutyType == e.key,
                      onSelected: (_) => setState(() {
                        _dutyType = e.key;
                        if (e.key != 'specialty' && _hospitalPost) _specialty = '';
                      }),
                    ),
              ]),
              const SizedBox(height: 14),
              if (!_hospitalPost || _dutyType == 'specialty') ...[
                _Label(_hospitalPost ? 'SPECIALTY' : 'SPECIALTY (OPTIONAL)'),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 320,
                  // ignore: deprecated_member_use
                  value: _specialty.isEmpty && _hospitalPost ? null : _specialty,
                  isExpanded: true,
                  hint: const Text('Pick the specialty'),
                  validator: (v) => _hospitalPost &&
                          _dutyType == 'specialty' &&
                          (v ?? '').isEmpty
                      ? 'Pick the specialty'
                      : null,
                  items: [
                    if (!_hospitalPost)
                      const DropdownMenuItem(value: '', child: Text('Any / general')),
                    for (final e in _Cp.specialties.entries)
                      DropdownMenuItem(
                          value: e.key, child: Text('${e.value.$1} ${e.value.$2}')),
                  ],
                  onChanged: (v) => setState(() => _specialty = v ?? ''),
                ),
                const SizedBox(height: 14),
              ],
              if (widget.team)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      _teamShift == 'all'
                          ? 'Full-time team: 3 nurses (A, B, C) from your partner agency work your hospital on a weekly rotation of Morning, Evening and Night, with no end date.'
                          : 'One full-time nurse works your ${_teamShift[0].toUpperCase()}${_teamShift.substring(1)} shift every day, with no end date. Use this to replace a team member who has left.',
                      style: const TextStyle(fontSize: 12.5, color: CpColors.ink)),
                ),
              if (widget.team) ...[
                const _Label('SHIFT TO BOOK'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in const {
                    'morning': 'Morning',
                    'evening': 'Evening',
                    'night': 'Night',
                    'all': 'All 3 (full team)',
                  }.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _teamShift == e.key,
                      onSelected: (_) => setState(() => _teamShift = e.key),
                    ),
                ]),
                const SizedBox(height: 14),
              ],
              _Label(_rotation ? 'STARTING DATE' : 'DATE'),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_Cp.dayLabel(draft, DateTime.now())),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
              const SizedBox(height: 14),
              if (!_rotation) ...[
              const _Label('SHIFT'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _Cp.slots.entries)
                  ChoiceChip(
                    label: Text(_hospitalPost
                        ? e.value.$1
                        : '${e.value.$1} · ${_Cp.timeRange({'date': '2026-01-01', 'start': e.value.$2, 'end': e.value.$3})}'),
                    selected: _slot == e.key,
                    onSelected: (_) => setState(() {
                      _slot = e.key;
                      _start = e.value.$2;
                      _end = e.value.$3;
                    }),
                  ),
              ]),
              if (!_hospitalPost) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(true),
                    style:
                        OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: Text('Starts $_start'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(false),
                    style:
                        OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: Text('Ends $_end'),
                  ),
                ),
              ]),
              ],
              const SizedBox(height: 14),
              ],
              if (!widget.team) ...[
              const _Label('PROCEDURES NEEDED (OPTIONAL)'),
              _multiChips({
                for (final e in _Cp.procedures.entries)
                  e.key: '${e.value.$1} ${e.value.$2}'
              }, _procedures, (k) => setState(() {
                    _procedures.contains(k)
                        ? _procedures.remove(k)
                        : _procedures.add(k);
                  })),
              const SizedBox(height: 4),
              const Text(
                  'Some procedures can be claimed only by verified nurses.',
                  style: TextStyle(fontSize: 12, color: CpColors.muted)),
              const SizedBox(height: 14),
              ],
              if (widget.team && !_rotation) ...[
                const _Label('HOW MANY CARE PHYSICIANS (2-50)'),
                TextFormField(
                  controller: _teamSize,
                  keyboardType: TextInputType.number,
                  inputFormatters: Validators.digitsInput(2),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim()) ?? 0;
                    return n < 2 || n > 50 ? 'Enter 2 to 50' : null;
                  },
                  decoration: const InputDecoration(hintText: 'e.g. 3'),
                ),
                const SizedBox(height: 14),
              ],
              if (_hospitalPost)
                Builder(builder: (context) {
                    final r = _rates?[_dutyType];
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                widget.team
                                    ? 'MONTHLY SALARY PER CARE PHYSICIAN'
                                    : 'RATE FOR THIS SHIFT',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: CpColors.ink)),
                            const SizedBox(height: 4),
                            Text(
                                r == null
                                    ? (_rates != null
                                        ? NurseDutyRates.notSetMessage
                                        : 'Loading…')
                                    : widget.team
                                        ? (r.monthlySalary == null
                                            ? NurseDutyRates.notSetMessage
                                            : '${formatInr(r.monthlySalary!)} / month')
                                        : formatInr(r.hospitalRate),
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: CpColors.navy)),
                            Text(
                                widget.team
                                    ? 'Fixed monthly salary for this duty type.'
                                    : 'Fixed price for this duty type.',
                                style: TextStyle(
                                    fontSize: 12, color: CpColors.muted)),
                          ]),
                    );
                  })
              else ...[
              _Label(_rotation
                  ? 'PAY PER DUTY (₹)'
                  : (widget.team ? 'PAY PER DOCTOR (₹)' : 'PAY FOR THIS SHIFT (₹)')),
              TextFormField(
                controller: _pay,
                keyboardType: TextInputType.number,
                inputFormatters: Validators.digitsInput(6),
                validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0
                    ? 'Enter the shift pay'
                    : null,
                decoration: const InputDecoration(hintText: 'e.g. 2500'),
              ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Urgent'),
                subtitle: const Text('Shown first with an URGENT tag'),
                value: _urgent,
                onChanged: (v) => setState(() => _urgent = v),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CpColors.navy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 50),
                ),
                child: Text(_saving
                    ? 'Posting…'
                    : (widget.team
                        ? 'Request team'
                        : (board.postedBy == 'hospital' ? 'Book locum' : 'Post shift'))),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class NursePostJobScreen extends StatefulWidget {
  final NurseShiftBoardScreen board;
  final Map<String, dynamic>? job;
  const NursePostJobScreen({super.key, required this.board, this.job});

  @override
  State<NursePostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<NursePostJobScreen>
    with _HospitalAreaPicker {
  @override
  NurseShiftBoardScreen get board => widget.board;

  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> get _j => widget.job ?? const {};
  late final _title = TextEditingController(
      text: (_j['title'] ?? 'Staff Nurse').toString());
  late final _unit = TextEditingController(text: (_j['unit'] ?? '').toString());
  late final _note =
      TextEditingController(text: (_j['timingNote'] ?? '').toString());
  late final _min = TextEditingController(
      text: _j['salaryMin'] == null ? '' : '${_j['salaryMin']}');
  late final _max = TextEditingController(
      text: _j['salaryMax'] == null ? '' : '${_j['salaryMax']}');
  late final _openings =
      TextEditingController(text: '${_j['openings'] ?? 1}');
  late final _benefits =
      TextEditingController(text: (_j['benefits'] ?? '').toString());
  late String _dutyType = (_j['dutyType'] ?? 'ward').toString();
  late String _timing = (_j['timing'] ?? 'full_time').toString();
  late final Set<String> _quals = _Cp.listOf(_j['qualifications']).toSet();
  late final Set<String> _procedures = _Cp.listOf(_j['procedures']).toSet();
  late bool _urgent = _j['urgent'] == true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    listenHospitalsAndAreas(
        hospitalId: _j['hospitalId']?.toString(),
        initialArea: _j['area']?.toString());
  }

  @override
  void dispose() {
    cancelPickers();
    for (final c in [_title, _unit, _note, _min, _max, _openings, _benefits]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!FormUtils.validate(_formKey)) return;
    setState(() => _saving = true);
    try {
      await _Cp.postJob(
        id: widget.job?['id']?.toString(),
        postedBy: board.postedBy,
        posterId: board.posterId,
        posterName: board.posterName,
        hospitalId: hospital!.id,
        hospitalName: hospital!.name,
        area: area!,
        title: _title.text.trim(),
        unit: _unit.text.trim(),
        dutyType: _dutyType,
        timing: _timing,
        timingNote: _note.text.trim(),
        salaryMin: int.tryParse(_min.text.trim()) ?? 0,
        salaryMax: int.tryParse(_max.text.trim()) ?? 0,
        openings: int.tryParse(_openings.text.trim()) ?? 1,
        qualifications: _quals.toList(),
        procedures: _procedures.toList(),
        benefits: _benefits.text.trim(),
        urgent: _urgent,
        active: _j['active'] != false,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'save the job')),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    String? money(String? v) =>
        (int.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter ₹ per month' : null;
    return ResponsiveCenter(
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.job == null ? 'Post a full-time job' : 'Edit job')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(Responsive.gutter(context)),
            children: [
              ...hospitalAndAreaFields(),
              const SizedBox(height: 14),
              const _Label('JOB TITLE'),
              TextFormField(
                controller: _title,
                validator: (v) =>
                    (v ?? '').trim().length < 3 ? 'Enter the job title' : null,
              ),
              const SizedBox(height: 14),
              const _Label('UNIT / WARD'),
              TextFormField(
                controller: _unit,
                decoration:
                    const InputDecoration(hintText: 'e.g. ICU / Cardiac Care'),
              ),
              const SizedBox(height: 14),
              const _Label('DUTY TYPE'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _Cp.dutyTypes.entries)
                  ChoiceChip(
                    label: Text('${e.value.$1} ${e.value.$2}'),
                    selected: _dutyType == e.key,
                    onSelected: (_) => setState(() => _dutyType = e.key),
                  ),
              ]),
              const SizedBox(height: 14),
              const _Label('TIMING'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _Cp.jobTimings.entries)
                  ChoiceChip(
                    label: Text('${e.value.$1} ${e.value.$2}'),
                    selected: _timing == e.key,
                    onSelected: (_) => setState(() => _timing = e.key),
                  ),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                    hintText: 'Timing note, e.g. 24×7 rotational (optional)'),
              ),
              const SizedBox(height: 14),
              const _Label('MONTHLY SALARY (₹)'),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    inputFormatters: Validators.digitsInput(7),
                    validator: money,
                    decoration: const InputDecoration(hintText: 'From'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _max,
                    keyboardType: TextInputType.number,
                    inputFormatters: Validators.digitsInput(7),
                    validator: money,
                    decoration: const InputDecoration(hintText: 'To'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    controller: _openings,
                    keyboardType: TextInputType.number,
                    inputFormatters: Validators.digitsInput(2),
                    validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0
                        ? 'Openings'
                        : null,
                    decoration: const InputDecoration(labelText: 'Openings'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              const _Label('QUALIFICATIONS ACCEPTED (NONE = ANY)'),
              _multiChips({for (final q in _Cp.qualifications.keys) q: q}, _quals,
                  (k) => setState(() {
                        _quals.contains(k) ? _quals.remove(k) : _quals.add(k);
                      })),
              const SizedBox(height: 14),
              const _Label('PROCEDURES NEEDED (OPTIONAL)'),
              _multiChips({
                for (final e in _Cp.procedures.entries)
                  e.key: '${e.value.$1} ${e.value.$2}'
              }, _procedures, (k) => setState(() {
                    _procedures.contains(k)
                        ? _procedures.remove(k)
                        : _procedures.add(k);
                  })),
              const SizedBox(height: 14),
              const _Label('BENEFITS (OPTIONAL)'),
              TextFormField(
                controller: _benefits,
                decoration: const InputDecoration(
                    hintText: 'e.g. PF + ESI + Accommodation available'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Urgent hiring'),
                value: _urgent,
                onChanged: (v) => setState(() => _urgent = v),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CpColors.navy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 50),
                ),
                child: Text(_saving
                    ? 'Saving…'
                    : (widget.job == null ? 'Post job' : 'Save changes')),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
