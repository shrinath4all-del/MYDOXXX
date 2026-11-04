import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../screens/chat/chat_screen.dart';
import '../utils/chat_access.dart';

/// Chat between the patient and the ambulance of an SOS request. It is open
/// only while the ambulance is on duty for the patient (dispatched, until the
/// handover at the hospital); after that the button is replaced by a note
/// that chat is unavailable.
class AmbulanceChatButton extends StatelessWidget {
  /// The SOS request (`appointments/{id}` data with its `appointmentId`).
  final Map<String, dynamic> sos;
  final String sosId;

  /// True on the ambulance's screen, false on the patient's.
  final bool forAmbulance;

  const AmbulanceChatButton({
    super.key,
    required this.sos,
    required this.sosId,
    required this.forAmbulance,
  });

  @override
  Widget build(BuildContext context) {
    final ambulanceUid = (sos['assignedAmbulanceUid'] ?? '').toString();
    final patientUid = (sos['patientUid'] ?? '').toString();
    if (ambulanceUid.isEmpty || patientUid.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!ChatAccess.ambulanceOnDuty(sos, ambulanceUid)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 16, color: AppColors.muted),
          SizedBox(width: 6),
          Expanded(
            child: Text('Ambulance chat is unavailable: the ambulance is off duty.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        ]),
      );
    }
    final driver = (sos['assignedAmbulanceDriver'] ?? 'Ambulance').toString();
    final patient = (sos['patientName'] ?? 'Patient').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44)),
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: Text(forAmbulance ? 'Chat with patient' : 'Chat with ambulance'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: '${patientUid}_$ambulanceUid',
            currentUserId: forAmbulance ? ambulanceUid : patientUid,
            currentUserName: forAmbulance ? driver : patient,
            peerName: forAmbulance ? patient : driver,
            peerRole: forAmbulance ? 'Patient' : 'Ambulance',
            allowVideo: false,
            ambulanceSosId: sosId,
          ),
        )),
      ),
    );
  }
}
