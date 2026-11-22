import 'package:flutter/material.dart';

import '../../../utils/duty_request_status.dart';

import '../../../models/care_duty_roster.dart';
import '../../../services/nurse_duty_service.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/stream_cache.dart';
import '../control_room_widgets.dart';
import 'nurse_profile_view_screen.dart';
import 'nurse_photo.dart';

/// Leave requests of an agency's nurses (or, for the MyDox admin
/// panel, of freelancers: [approverId] is [NurseDutyService.platformId]).
/// The agency approves or declines; an approved leave is then offered to the
/// agency's other nurses as cover.
class NurseLeaveRequestsScreen extends StatefulWidget {
  final String approverId;
  final String title;
  const NurseLeaveRequestsScreen(
      {super.key, required this.approverId, this.title = 'Leave requests'});

  @override
  State<NurseLeaveRequestsScreen> createState() => _LeaveRequestsScreenState();
}

class _LeaveRequestsScreenState extends State<NurseLeaveRequestsScreen> {
  final StreamCache _streams = StreamCache();
  bool _busy = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec'
  ];

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await NurseDutyService.decideLeave(r['id'].toString(),
          approve: approve, approverId: widget.approverId);
      messenger.showSnackBar(SnackBar(
          content: Text(approve ? 'Leave approved.' : 'Leave declined.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(ErrorMessages.of(e, action: 'answer the leave request'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ControlRoomColors.page,
      appBar: AppBar(title: Text(widget.title)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('leave',
            () => NurseDutyService.leaveRequestsOfAgency(widget.approverId)),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load the leave requests: ${snap.error}'),
            ));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No leave requests yet.',
                  style: TextStyle(color: ControlRoomColors.muted)),
            ));
          }
          final waiting =
              list.where((r) => DutyRequestStatus.awaitingApproval(r['status'])).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              MaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                          waiting == 0
                              ? 'Nothing waits for your answer.'
                              : '$waiting waiting for your answer',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: ControlRoomColors.ink)),
                    ),
                    for (final r in list) _card(r),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    final slot = DutySlot.parse((r['sourceKey'] ?? '').toString());
    final name = (r['requesterName'] ?? 'Nurse').toString();
    final uid = (r['requesterUid'] ?? '').toString();
    final (label, color) = switch (status) {
      'awaiting_agency' || 'awaiting_hospital' => ('NEEDS YOUR ANSWER', ControlRoomColors.orange),
      'declined' => ('DECLINED', ControlRoomColors.red),
      'accepted' => ('COVERED', ControlRoomColors.green),
      'withdrawn' => ('WITHDRAWN', ControlRoomColors.muted),
      _ => ('APPROVED', ControlRoomColors.green),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: controlRoomBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => NurseProfileViewScreen.open(context, uid, name: name),
            child: Row(children: [
              NursePhoto(uid: uid, name: name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: ControlRoomColors.ink)),
                      Text((r['hospitalName'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 12.5, color: ControlRoomColors.muted)),
                    ]),
              ),
              StatusBadge(label, color),
            ]),
          ),
          const SizedBox(height: 8),
          if (slot != null)
            Text(
                '${slot.date.day} ${_months[slot.date.month - 1]} ${slot.date.year} · ${slot.shift.label} ${slot.shift.timeText}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          if ((r['reason'] ?? '').toString().isNotEmpty)
            Text('Reason: ${r['reason']}',
                style: const TextStyle(fontSize: 12.5)),
          if ((r['note'] ?? '').toString().isNotEmpty)
            Text('${r['note']}',
                style: const TextStyle(
                    fontSize: 12.5, color: ControlRoomColors.muted)),
          if (status == 'accepted' &&
              (r['acceptedByName'] ?? '').toString().isNotEmpty)
            Text('Covered by ${r['acceptedByName']}',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (DutyRequestStatus.awaitingApproval(status)) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: _busy ? null : () => _decide(r, false),
                    child: const Text('Decline')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                    onPressed: _busy ? null : () => _decide(r, true),
                    child: const Text('Approve leave')),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
