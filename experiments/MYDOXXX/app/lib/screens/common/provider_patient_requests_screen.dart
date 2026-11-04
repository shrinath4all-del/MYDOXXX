import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/error_messages.dart';
import '../chat/chat_screen.dart';

/// Patient home bookings already live in appointments. Staffing duties remain
/// in nurse_shifts/technician_shifts: opening this view never copies a booking.
class ProviderPatientRequests {
  static bool canClaim(Map<String, dynamic> booking, String uid) {
    if ((booking['declinedBy'] as List? ?? const []).contains(uid))
      return false;
    final status = booking['status'];
    final target = booking['doctorUid'] ?? '';
    return status == 'Broadcasted' ||
        (status == 'Pending Home Visit' && target == uid);
  }

  static bool isMine(Map<String, dynamic> booking, String uid) =>
      booking['doctorUid'] == uid;
  static Stream<List<Map<String, dynamic>>> stream(UserModel user) =>
      user.isNurse
          ? FirestoreService.getNurseBookingsStream(
              user.uid, user.preferredLocations ?? [])
          : FirestoreService.getTechnicianBookingsStream(
              user.uid, user.preferredLocations ?? []);
}

class ProviderPatientRequestsButton extends StatefulWidget {
  const ProviderPatientRequestsButton({super.key, required this.user});
  final UserModel user;
  @override
  State<ProviderPatientRequestsButton> createState() =>
      _ProviderPatientRequestsButtonState();
}

class _ProviderPatientRequestsButtonState
    extends State<ProviderPatientRequestsButton> {
  late final _stream = ProviderPatientRequests.stream(widget.user);
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          final count = (snapshot.data ?? [])
              .where(
                  (b) => ProviderPatientRequests.canClaim(b, widget.user.uid))
              .length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      child: const Icon(Icons.home_work_outlined)),
                  label: Text(snapshot.hasError
                      ? 'Patient requests • retry connection'
                      : 'Patient requests & chats${count > 0 ? ' ($count new)' : ''}'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          ProviderPatientRequestsScreen(user: widget.user))),
                )),
          );
        },
      );
}

class ProviderPatientRequestsScreen extends StatefulWidget {
  const ProviderPatientRequestsScreen({super.key, required this.user});
  final UserModel user;
  @override
  State<ProviderPatientRequestsScreen> createState() =>
      _ProviderPatientRequestsScreenState();
}

class _ProviderPatientRequestsScreenState
    extends State<ProviderPatientRequestsScreen> {
  late final _stream = ProviderPatientRequests.stream(widget.user);
  final Set<String> _busy = {};
  String _id(Map<String, dynamic> b) =>
      (b['appointmentId'] ?? b['id']).toString();
  void _notice(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _act(Map<String, dynamic> b, String action) async {
    final id = _id(b);
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      if (action == 'accept') {
        final accepted = await FirestoreService.acceptProviderRequest(
            appointmentId: id,
            providerUid: widget.user.uid,
            providerName: widget.user.name);
        _notice(accepted
            ? 'Accepted. The patient sees your response now.'
            : 'This request is no longer available.');
      } else if (action == 'decline') {
        await FirestoreService.declineProviderRequest(
            appointmentId: id, providerUid: widget.user.uid);
        _notice('Request declined.');
      } else if (action == 'start') {
        final controller = TextEditingController();
        final code = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: const Text('Enter patient OTP'),
                  content: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: '4-digit booking OTP')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, controller.text),
                        child: const Text('Start visit'))
                  ],
                ));
        // Dialog route disposes its text field after its closing animation.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        controller.dispose();
        if (code == null || code.isEmpty) return;
        final result = await FirestoreService.startSessionWithOtp(
            appointmentId: id, enteredOtp: code);
        _notice(result == null ? 'That OTP is incorrect.' : 'Visit started.');
      } else if (action == 'complete') {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: const Text('Complete this visit?'),
                  content: const Text(
                      'Confirm after providing the booked care. The patient can then use follow-up chat.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Complete'))
                  ],
                ));
        if (confirmed != true) return;
        await FirestoreService.completeConsultation(id);
        _notice('Visit completed. Follow-up chat is available.');
      }
    } catch (e) {
      _notice(ErrorMessages.of(e, action: 'update this request'));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Patient requests & chats')),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError)
              return const Center(
                  child: Text(
                      'Unable to load requests. Check your test connection.'));
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            final bookings = snap.data!
                .where((b) =>
                    b['declinedByMe'] != true &&
                    (ProviderPatientRequests.canClaim(b, widget.user.uid) ||
                        ProviderPatientRequests.isMine(b, widget.user.uid)))
                .toList()
              ..sort((a, b) => (b['createdAt'] ?? '')
                  .toString()
                  .compareTo((a['createdAt'] ?? '').toString()));
            if (bookings.isEmpty)
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'No patient requests yet. Book a home visit from the Patient panel to see it here.',
                          textAlign: TextAlign.center)));
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: bookings.length,
              itemBuilder: (context, index) {
                final b = bookings[index];
                final busy = _busy.contains(_id(b));
                final mine = ProviderPatientRequests.isMine(b, widget.user.uid);
                final canClaim =
                    ProviderPatientRequests.canClaim(b, widget.user.uid);
                Widget button(String label, String action) => OutlinedButton(
                    onPressed: busy ? null : () => _act(b, action),
                    child: Text(label));
                return Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((b['patientName'] ?? 'Patient').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 17)),
                            const SizedBox(height: 8),
                            Text(
                                '${b['consultationType'] ?? 'Home visit'}\n${b['date'] ?? ''} • ${b['time'] ?? ''}'),
                            Text('${b['status']} • ₹${b['price'] ?? 0}'),
                            if (b['paymentStatus'] == 'pending')
                              const Text('Patient payment pending',
                                  style: TextStyle(color: Colors.orange)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              if (canClaim) ...[
                                button('Accept', 'accept'),
                                button('Decline', 'decline')
                              ],
                              if (mine && b['status'] == 'Confirmed')
                                button('Enter OTP / start', 'start'),
                              if (mine && b['status'] == 'In Progress')
                                button('Complete visit', 'complete'),
                              if (mine && b['status'] == 'Completed')
                                OutlinedButton.icon(
                                    icon: const Icon(Icons.chat_bubble_outline),
                                    label: const Text('Follow-up chat'),
                                    onPressed: () => Navigator.of(context)
                                        .push(MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                                  chatId:
                                                      '${b['patientUid']}_${widget.user.uid}',
                                                  currentUserId:
                                                      widget.user.uid,
                                                  currentUserName:
                                                      widget.user.name,
                                                  peerName: (b['patientName'] ??
                                                          'Patient')
                                                      .toString(),
                                                  peerRole: 'Patient',
                                                  allowVideo: false,
                                                )))),
                            ]),
                            if (busy) const LinearProgressIndicator(),
                          ],
                        )));
              },
            );
          },
        ),
      );
}
